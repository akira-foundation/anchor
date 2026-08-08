import AnchorDomain

public protocol StorageProvider: Sendable {
    func putObject(_ storageObject: StorageObject) async throws(StorageFailure)
    func object(for key: StorageKey) async throws(StorageFailure) -> StorageObject?
    func deleteObject(for key: StorageKey) async throws(StorageFailure)
    func listObjects(
        withPrefix prefix: StorageKey?
    ) async throws(StorageFailure)
        -> [StorageObjectMetadata]
    func observeChanges(
        after cursor: StorageCursor?
    ) -> AsyncThrowingStream<StorageChange, any Error>
}
