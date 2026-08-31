import AnchorStorage
import CloudKit
import Foundation

enum CloudKitFailureMapping {
    private static let absenceCodes: Set<CKError.Code> = [.unknownItem, .zoneNotFound]

    static func failure(from error: any Error) -> CloudDatabaseFailure {
        guard let code = (error as? CKError)?.code else { return .transportUnavailable }

        switch code {
        case .partialFailure:
            return failure(explaining: partialRefusals(in: error)) ?? .transportUnavailable
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

    static func failure(explaining batch: [any Error]) -> CloudDatabaseFailure? {
        guard !batch.isEmpty else { return nil }

        let causes =
            batch
            .filter { (($0 as? CKError)?.code != .batchRequestFailed) }
            .map(failure(from:))
            .sorted { urgency(of: $0) < urgency(of: $1) }

        return causes.first ?? .transportUnavailable
    }

    static func failure(
        explainingSaves saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
        deletes deleteResults: [CKRecord.ID: Result<Void, any Error>]
    ) -> CloudDatabaseFailure? {
        let refusedSaves = saveResults.values.compactMap(\.refusal)
        let refusedDeletes = deleteResults.values.compactMap(\.refusal).filter { !isAbsence($0) }

        return failure(explaining: refusedSaves + refusedDeletes)
    }

    static func isAbsence(_ error: any Error) -> Bool {
        guard let code = (error as? CKError)?.code else { return false }

        return absenceCodes.contains(code)
    }

    private static func urgency(of failure: CloudDatabaseFailure) -> Int {
        switch failure {
        case .accountUnavailable: return 0
        case .quotaExceeded: return 1
        case .versionTagMismatch: return 2
        case .changeTokenExpired: return 3
        case .transportUnavailable: return 4
        }
    }

    private static func partialRefusals(in error: any Error) -> [any Error] {
        guard let refusals = (error as? CKError)?.partialErrorsByItemID?.values else { return [] }

        return refusals.filter { (($0 as? CKError)?.code != .partialFailure) }
    }

    private static func serverVersionTag(in error: any Error) -> StorageVersionTag? {
        guard let serverRecord = (error as? CKError)?.serverRecord,
            let changeTag = serverRecord.recordChangeTag
        else { return nil }

        return StorageVersionTag(rawValue: changeTag)
    }
}

extension Result {
    fileprivate var refusal: Failure? {
        guard case .failure(let refusal) = self else { return nil }

        return refusal
    }
}
