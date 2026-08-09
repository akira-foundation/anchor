public struct StoredObject: Sendable, Hashable {
    public let object: StorageObject
    public let metadata: StorageObjectMetadata

    public init(object: StorageObject, metadata: StorageObjectMetadata) {
        self.object = object
        self.metadata = metadata
    }
}
