import AnchorDomain
import AnchorStorage
import AnchorStorageTestSupport
import Foundation
import Testing

actor InMemoryStorageProvider: StorageProvider {
    private var storedObjectsByKey: [StorageKey: StorageObject] = [:]
    private var metadataByKey: [StorageKey: StorageObjectMetadata] = [:]
    private var writeSequenceNumber = 0

    func putObject(_ storageObject: StorageObject) async throws(StorageFailure) {
        let existingMetadata = metadataByKey[storageObject.key]

        if let expectedVersionTag = storageObject.expectedVersionTag {
            guard existingMetadata?.versionTag == expectedVersionTag else {
                throw .versionConflict(storageObject.key)
            }
        }

        writeSequenceNumber += 1
        storedObjectsByKey[storageObject.key] = storageObject
        metadataByKey[storageObject.key] = StorageObjectMetadata(
            key: storageObject.key,
            byteSize: storageObject.contents.count,
            modifiedAt: Date(timeIntervalSince1970: TimeInterval(writeSequenceNumber)),
            versionTag: StorageVersionTag(rawValue: String(writeSequenceNumber))
        )
    }

    func object(for key: StorageKey) async throws(StorageFailure) -> StorageObject? {
        storedObjectsByKey[key]
    }

    func deleteObject(for key: StorageKey) async throws(StorageFailure) {
        guard storedObjectsByKey.removeValue(forKey: key) != nil else {
            throw .objectNotFound(key)
        }

        metadataByKey.removeValue(forKey: key)
    }

    func listObjects(
        withPrefix prefix: StorageKey?
    ) async throws(StorageFailure)
        -> [StorageObjectMetadata]
    {
        metadataByKey.values
            .filter { prefix.map { $0.rawValue }.map($0.key.rawValue.hasPrefix) ?? true }
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    nonisolated func observeChanges(
        after cursor: StorageCursor?
    )
        -> AsyncThrowingStream<StorageChange, any Error>
    {
        AsyncThrowingStream { $0.finish() }
    }

}

@Suite("InMemoryStorageProvider conforms to the StorageProvider contract")
struct InMemoryStorageProviderTests {
    @Test("the in memory provider satisfies every contract expectation")
    func inMemoryProviderSatisfiesEveryContractExpectation() async throws {
        try await verifyStorageProviderConformance { InMemoryStorageProvider() }
    }
}
