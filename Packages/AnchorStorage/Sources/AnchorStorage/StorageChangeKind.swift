public enum StorageChangeKind: String, Sendable, Hashable, Codable {
    case created
    case updated
    case deleted
}
