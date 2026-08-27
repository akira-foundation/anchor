import AnchorDomain
import Foundation

public actor FileSystemStorageProvider: StorageProvider {
    private static let objectFileName = "object.data"

    private let rootURL: URL
    private var recordedChanges: [StorageChange] = []
    private var observerContinuations:
        [Int: AsyncThrowingStream<StorageChange, any Error>.Continuation] = [:]
    private var observerSequenceNumber = 0

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    @discardableResult
    public func putObject(
        _ storageObject: StorageObject, precondition: StorageWritePrecondition
    ) async throws(StorageFailure) -> StorageObjectMetadata {
        let existingMetadata = readMetadata(for: storageObject.key)
        try verifyPrecondition(precondition, for: storageObject.key, against: existingMetadata)

        let fileURL = fileURL(for: storageObject.key)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try storageObject.contents.write(to: fileURL, options: .atomic)
        } catch {
            throw StorageFailure.transportUnavailable
        }

        recordChange(key: storageObject.key, kind: existingMetadata == nil ? .created : .updated)

        guard let writtenMetadata = readMetadata(for: storageObject.key) else {
            throw StorageFailure.transportUnavailable
        }

        return writtenMetadata
    }

    public func object(for key: StorageKey) async throws(StorageFailure) -> StoredObject? {
        guard let contents = try? Data(contentsOf: fileURL(for: key)),
            let metadata = readMetadata(for: key)
        else {
            return nil
        }

        return StoredObject(
            object: StorageObject(key: key, contents: contents), metadata: metadata
        )
    }

    public func deleteObject(for key: StorageKey) async throws(StorageFailure) {
        guard readMetadata(for: key) != nil else { return }

        do {
            try FileManager.default.removeItem(at: fileURL(for: key))
        } catch {
            throw StorageFailure.transportUnavailable
        }

        recordChange(key: key, kind: .deleted)
    }

    public func listObjects(
        withPrefix prefix: StorageKey?
    ) async throws(StorageFailure) -> [StorageObjectMetadata] {
        storedKeys()
            .filter { key in prefix.map(key.isWithin) ?? true }
            .compactMap(readMetadata)
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    nonisolated public func observeChanges(
        after cursor: StorageCursor?
    ) -> AsyncThrowingStream<StorageChange, any Error> {
        AsyncThrowingStream { continuation in
            Task { await self.registerObserver(continuation, after: cursor) }
        }
    }

    private func registerObserver(
        _ continuation: AsyncThrowingStream<StorageChange, any Error>.Continuation,
        after cursor: StorageCursor?
    ) {
        for change in changes(after: cursor) { continuation.yield(change) }

        observerSequenceNumber += 1
        observerContinuations[observerSequenceNumber] = continuation
    }

    private func changes(after cursor: StorageCursor?) -> [StorageChange] {
        guard let cursor, let index = recordedChanges.firstIndex(where: { $0.cursor == cursor })
        else {
            return recordedChanges
        }

        return Array(recordedChanges[recordedChanges.index(after: index)...])
    }

    private func recordChange(key: StorageKey, kind: StorageChangeKind) {
        let change = StorageChange(
            key: key,
            kind: kind,
            cursor: StorageCursor(rawValue: String(recordedChanges.count + 1))
        )
        recordedChanges.append(change)
        for continuation in observerContinuations.values { continuation.yield(change) }
    }

    private func verifyPrecondition(
        _ precondition: StorageWritePrecondition,
        for key: StorageKey,
        against existingMetadata: StorageObjectMetadata?
    ) throws(StorageFailure) {
        switch precondition {
        case .none:
            return
        case .objectIsAbsent:
            guard existingMetadata == nil else {
                throw StorageFailure.preconditionFailed(
                    key, currentVersionTag: existingMetadata?.versionTag
                )
            }
        case .versionTagMatches(let expectedTag):
            guard existingMetadata?.versionTag == expectedTag else {
                throw StorageFailure.preconditionFailed(
                    key, currentVersionTag: existingMetadata?.versionTag
                )
            }
        }
    }

    private func readMetadata(for key: StorageKey) -> StorageObjectMetadata? {
        let fileURL = fileURL(for: key)
        guard let contents = try? Data(contentsOf: fileURL),
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path())
        else {
            return nil
        }

        return StorageObjectMetadata(
            key: key,
            byteSize: contents.count,
            modifiedAt: attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0),
            versionTag: StorageVersionTag(rawValue: ContentHash.digest(of: contents).rawValue)
        )
    }

    private func storedKeys() -> [StorageKey] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: rootURL, includingPropertiesForKeys: [.isRegularFileKey]
            )
        else {
            return []
        }

        return enumerator.allObjects.compactMap { element in
            guard let fileURL = element as? URL,
                fileURL.lastPathComponent == Self.objectFileName,
                (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else {
                return nil
            }

            return relativeKey(of: fileURL.deletingLastPathComponent())
        }
    }

    private func relativeKey(of directoryURL: URL) -> StorageKey? {
        let root = rootURL.resolvingSymlinksInPath().path()
        let prefix = root.hasSuffix("/") ? root : root + "/"
        var path = directoryURL.resolvingSymlinksInPath().path()
        while path.hasSuffix("/") { path.removeLast() }
        guard path.hasPrefix(prefix) else { return nil }

        return StorageKey(rawValue: String(path.dropFirst(prefix.count)))
    }

    private func fileURL(for key: StorageKey) -> URL {
        rootURL.appending(path: key.rawValue).appending(path: Self.objectFileName)
    }
}
