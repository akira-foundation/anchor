public enum StorageReadFailure: Error, Sendable, Equatable {
    case noStoredDataAtRelativePath(String)
}
