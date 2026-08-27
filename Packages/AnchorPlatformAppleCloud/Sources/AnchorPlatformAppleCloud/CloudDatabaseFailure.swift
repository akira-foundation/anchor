import AnchorStorage

public enum CloudDatabaseFailure: Error, Sendable, Equatable {
    case versionTagMismatch(currentVersionTag: StorageVersionTag?)
    case changeTokenExpired
    case accountUnavailable
    case quotaExceeded
    case transportUnavailable
}
