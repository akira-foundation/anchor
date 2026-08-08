import AnchorDomain

public enum StorageFailure: Error, Sendable, Equatable {
    case preconditionFailed(StorageKey, currentVersionTag: StorageVersionTag?)
    case transportUnavailable
}
