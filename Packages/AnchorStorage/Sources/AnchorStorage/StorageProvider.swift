import AnchorDomain

public protocol StorageProvider: Sendable {
    @discardableResult
    func putObject(
        _ storageObject: StorageObject, precondition: StorageWritePrecondition
    )
        async throws(StorageFailure) -> StorageObjectMetadata

    func object(for key: StorageKey) async throws(StorageFailure) -> StoredObject?

    func deleteObject(for key: StorageKey) async throws(StorageFailure)

    func listObjects(
        withPrefix prefix: StorageKey?
    ) async throws(StorageFailure)
        -> [StorageObjectMetadata]

    func observeChanges(
        after cursor: StorageCursor?
    ) -> AsyncThrowingStream<StorageChange, any Error>
}

extension StorageKey {
    public func isWithin(_ prefix: StorageKey) -> Bool {
        rawValue == prefix.rawValue || rawValue.hasPrefix(prefix.rawValue + "/")
    }
}
