import AnchorApplication
import AnchorStorage

public struct StorageFailureClassifier: SyncFailureClassifying {
    public init() {}

    public func isWorthRetrying(_ failure: any Error) -> Bool {
        guard let storageFailure = failure as? StorageFailure else { return false }

        switch storageFailure {
        case .transportUnavailable:
            return true
        case .preconditionFailed, .accountUnavailable, .quotaExceeded, .contentUnreadable:
            return false
        }
    }
}
