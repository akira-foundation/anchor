import AnchorDomain
import AnchorStorage
import Foundation

public actor CloudKitStorageProvider: StorageProvider {
    private let database: any CloudRecordDatabase
    private let pollInterval: Duration
    private let now: @Sendable () -> Date

    public init(
        database: any CloudRecordDatabase,
        pollInterval: Duration = .milliseconds(250),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.database = database
        self.pollInterval = pollInterval
        self.now = now
    }

    @discardableResult
    public func putObject(
        _ storageObject: StorageObject, precondition: StorageWritePrecondition
    ) async throws(StorageFailure) -> StorageObjectMetadata {
        let name = CloudRecordNaming.objectRecordName(for: storageObject.key)
        let existing = try await snapshot(named: name, for: storageObject.key)
        let entry = makeLogEntry(
            for: storageObject.key, kind: existing == nil ? .created : .updated)
        let draft = CloudRecordDraft(
            name: name, key: storageObject.key, contents: storageObject.contents)

        do {
            let saved = try await database.save(draft, precondition: precondition, recording: entry)

            return metadata(from: saved)
        } catch {
            throw storageFailure(from: error, for: storageObject.key)
        }
    }

    public func object(for key: StorageKey) async throws(StorageFailure) -> StoredObject? {
        let name = CloudRecordNaming.objectRecordName(for: key)

        guard let snapshot = try await snapshot(named: name, for: key),
            let contents = snapshot.contents
        else { return nil }

        return StoredObject(
            object: StorageObject(key: key, contents: contents),
            metadata: metadata(from: snapshot)
        )
    }

    public func deleteObject(for key: StorageKey) async throws(StorageFailure) {
        let name = CloudRecordNaming.objectRecordName(for: key)

        guard try await snapshot(named: name, for: key) != nil else { return }

        do {
            try await database.remove(
                recordNamed: name, recording: makeLogEntry(for: key, kind: .deleted))
        } catch {
            throw storageFailure(from: error, for: key)
        }
    }

    public func listObjects(
        withPrefix prefix: StorageKey?
    ) async throws(StorageFailure) -> [StorageObjectMetadata] {
        let snapshots: [CloudRecordSnapshot]

        do {
            snapshots = try await database.objectSnapshots()
        } catch {
            throw storageFailure(fromReadThatCarriesNoPrecondition: error)
        }

        return
            snapshots
            .filter { prefix.map($0.key.isWithin) ?? true }
            .map(metadata(from:))
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    public nonisolated func observeChanges(
        after cursor: StorageCursor?
    ) -> AsyncThrowingStream<StorageChange, any Error> {
        let resumePoint = CloudChangeCursor.resumePoint(from: cursor)

        return AsyncThrowingStream { continuation in
            let streaming = Task {
                await self.streamChanges(from: resumePoint, into: continuation)
            }

            continuation.onTermination = { _ in streaming.cancel() }
        }
    }

    private func streamChanges(
        from resumePoint: (pageToken: Data?, entriesToSkip: Int),
        into continuation: AsyncThrowingStream<StorageChange, any Error>.Continuation
    ) async {
        var pageToken = resumePoint.pageToken
        var entriesToSkip = resumePoint.entriesToSkip

        while !Task.isCancelled {
            let page: CloudLogPage

            do {
                page = try await database.logEntries(after: pageToken)
            } catch .changeTokenExpired {
                pageToken = nil
                entriesToSkip = 0
                continue
            } catch {
                continuation.finish(
                    throwing: storageFailure(fromReadThatCarriesNoPrecondition: error))
                return
            }

            for (index, entry) in page.entries.enumerated() where index >= entriesToSkip {
                continuation.yield(
                    StorageChange(
                        key: entry.key,
                        kind: entry.kind,
                        cursor: CloudChangeCursor.cursor(pageToken: pageToken, entryIndex: index)
                    )
                )
            }

            pageToken = page.token
            entriesToSkip = 0

            guard !page.hasMore else { continue }

            try? await Task.sleep(for: pollInterval)
        }

        continuation.finish()
    }

    private func snapshot(
        named name: String, for key: StorageKey
    ) async throws(StorageFailure) -> CloudRecordSnapshot? {
        do {
            return try await database.snapshot(named: name)
        } catch {
            throw storageFailure(from: error, for: key)
        }
    }

    private func makeLogEntry(for key: StorageKey, kind: StorageChangeKind) -> CloudLogEntry {
        CloudLogEntry(
            name: CloudRecordNaming.logRecordName(
                recordedAt: now(), disambiguator: UUID().uuidString),
            key: key,
            kind: kind
        )
    }

    private func metadata(from snapshot: CloudRecordSnapshot) -> StorageObjectMetadata {
        StorageObjectMetadata(
            key: snapshot.key,
            byteSize: snapshot.byteSize,
            modifiedAt: snapshot.modifiedAt,
            versionTag: snapshot.versionTag
        )
    }

    private func storageFailure(
        from failure: CloudDatabaseFailure, for key: StorageKey
    ) -> StorageFailure {
        switch failure {
        case .versionTagMismatch(let currentVersionTag):
            return .preconditionFailed(key, currentVersionTag: currentVersionTag)
        case .accountUnavailable: return .accountUnavailable
        case .quotaExceeded: return .quotaExceeded
        case .changeTokenExpired, .transportUnavailable: return .transportUnavailable
        }
    }

    private func storageFailure(
        fromReadThatCarriesNoPrecondition failure: CloudDatabaseFailure
    ) -> StorageFailure {
        switch failure {
        case .accountUnavailable: return .accountUnavailable
        case .quotaExceeded: return .quotaExceeded
        case .versionTagMismatch, .changeTokenExpired, .transportUnavailable:
            return .transportUnavailable
        }
    }
}
