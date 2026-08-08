import AnchorDomain

public struct StorageChange: Sendable, Hashable, Codable {
    public let key: StorageKey
    public let kind: StorageChangeKind
    public let cursor: StorageCursor

    public init(key: StorageKey, kind: StorageChangeKind, cursor: StorageCursor) {
        self.key = key
        self.kind = kind
        self.cursor = cursor
    }
}
