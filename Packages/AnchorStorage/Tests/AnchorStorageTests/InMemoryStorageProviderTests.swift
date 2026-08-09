import AnchorDomain
import AnchorStorage
import AnchorStorageTestSupport
import Foundation
import Testing

actor InMemoryStorageProvider: StorageProvider {
    private var storedObjectsByKey: [StorageKey: StoredObject] = [:]
    private var recordedChanges: [StorageChange] = []
    private var observerContinuations:
        [Int: AsyncThrowingStream<StorageChange, any Error>.Continuation] = [:]
    private var writeSequenceNumber = 0
    private var observerSequenceNumber = 0

    @discardableResult
    func putObject(
        _ storageObject: StorageObject, precondition: StorageWritePrecondition
    )
        async throws(StorageFailure) -> StorageObjectMetadata
    {
        let existingMetadata = storedObjectsByKey[storageObject.key]?.metadata

        try verifyPrecondition(precondition, for: storageObject.key, against: existingMetadata)

        writeSequenceNumber += 1

        let writtenMetadata = StorageObjectMetadata(
            key: storageObject.key,
            byteSize: storageObject.contents.count,
            modifiedAt: Date(timeIntervalSince1970: TimeInterval(writeSequenceNumber)),
            versionTag: StorageVersionTag(rawValue: String(writeSequenceNumber))
        )

        storedObjectsByKey[storageObject.key] = StoredObject(
            object: storageObject,
            metadata: writtenMetadata
        )
        recordChange(key: storageObject.key, kind: existingMetadata == nil ? .created : .updated)

        return writtenMetadata
    }

    func object(for key: StorageKey) async throws(StorageFailure) -> StoredObject? {
        storedObjectsByKey[key]
    }

    func deleteObject(for key: StorageKey) async throws(StorageFailure) {
        guard storedObjectsByKey.removeValue(forKey: key) != nil else { return }

        recordChange(key: key, kind: .deleted)
    }

    func listObjects(
        withPrefix prefix: StorageKey?
    ) async throws(StorageFailure)
        -> [StorageObjectMetadata]
    {
        storedObjectsByKey.values
            .map(\.metadata)
            .filter { metadata in prefix.map(metadata.key.isWithin) ?? true }
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    nonisolated func observeChanges(
        after cursor: StorageCursor?
    )
        -> AsyncThrowingStream<StorageChange, any Error>
    {
        AsyncThrowingStream { continuation in
            let registration = Task {
                await self.startObserving(continuation, after: cursor)
            }

            continuation.onTermination = { _ in registration.cancel() }
        }
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
            guard existingMetadata != nil else { return }

            throw .preconditionFailed(key, currentVersionTag: existingMetadata?.versionTag)
        case .versionTagMatches(let expectedVersionTag):
            guard existingMetadata?.versionTag != expectedVersionTag else { return }

            throw .preconditionFailed(key, currentVersionTag: existingMetadata?.versionTag)
        }
    }

    private func recordChange(key: StorageKey, kind: StorageChangeKind) {
        let change = StorageChange(
            key: key,
            kind: kind,
            cursor: StorageCursor(rawValue: String(recordedChanges.count + 1))
        )

        recordedChanges.append(change)
        observerContinuations.values.forEach { $0.yield(change) }
    }

    private func startObserving(
        _ continuation: AsyncThrowingStream<StorageChange, any Error>.Continuation,
        after cursor: StorageCursor?
    ) {
        let replayStartIndex = cursor.flatMap { Int($0.rawValue) } ?? 0

        recordedChanges.dropFirst(replayStartIndex).forEach { continuation.yield($0) }

        observerSequenceNumber += 1
        observerContinuations[observerSequenceNumber] = continuation
    }
}

@Suite("InMemoryStorageProvider conforms to the StorageProvider contract")
struct InMemoryStorageProviderTests {
    @Test("the in memory provider satisfies every contract expectation")
    func inMemoryProviderSatisfiesEveryContractExpectation() async throws {
        try await verifyStorageProviderConformance { InMemoryStorageProvider() }
    }
}
