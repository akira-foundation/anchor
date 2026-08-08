import AnchorDomain

public enum StorageFailure: Error, Sendable, Equatable {
    case objectNotFound(StorageKey)
    case versionConflict(StorageKey)
    case transportUnavailable
}
