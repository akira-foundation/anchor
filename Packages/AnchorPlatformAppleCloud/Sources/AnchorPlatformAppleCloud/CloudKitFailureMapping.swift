import AnchorStorage
import CloudKit
import Foundation

enum CloudKitFailureMapping {
    static func failure(from error: any Error) -> CloudDatabaseFailure {
        guard let code = (error as? CKError)?.code else { return .transportUnavailable }

        switch code {
        case .serverRecordChanged:
            return .versionTagMismatch(currentVersionTag: serverVersionTag(in: error))
        case .changeTokenExpired:
            return .changeTokenExpired
        case .notAuthenticated, .managedAccountRestricted:
            return .accountUnavailable
        case .quotaExceeded:
            return .quotaExceeded
        default:
            return .transportUnavailable
        }
    }

    private static func serverVersionTag(in error: any Error) -> StorageVersionTag? {
        guard let serverRecord = (error as? CKError)?.serverRecord,
            let changeTag = serverRecord.recordChangeTag
        else { return nil }

        return StorageVersionTag(rawValue: changeTag)
    }
}
