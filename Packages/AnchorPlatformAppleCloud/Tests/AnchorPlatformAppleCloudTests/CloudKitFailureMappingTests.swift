import AnchorStorage
import CloudKit
import Foundation
import Testing

@testable import AnchorPlatformAppleCloud

@Suite("CloudKit failure mapping")
struct CloudKitFailureMappingTests {
    private func cloudKitError(_ code: CKError.Code) -> CKError {
        CKError(_nsError: NSError(domain: CKError.errorDomain, code: code.rawValue))
    }

    @Test(
        "each condition the caller must treat differently keeps its own name",
        arguments: [
            (
                CKError.Code.serverRecordChanged,
                CloudDatabaseFailure.versionTagMismatch(currentVersionTag: nil)
            ),
            (CKError.Code.changeTokenExpired, CloudDatabaseFailure.changeTokenExpired),
            (CKError.Code.notAuthenticated, CloudDatabaseFailure.accountUnavailable),
            (CKError.Code.quotaExceeded, CloudDatabaseFailure.quotaExceeded),
            (CKError.Code.networkUnavailable, CloudDatabaseFailure.transportUnavailable),
        ]
    )
    func eachConditionTheCallerMustTreatDifferentlyKeepsItsOwnName(
        code: CKError.Code, expected: CloudDatabaseFailure
    ) {
        #expect(CloudKitFailureMapping.failure(from: cloudKitError(code)) == expected)
    }

    @Test("an error that is not CloudKit's is treated as transport")
    func errorThatIsNotCloudKitsIsTreatedAsTransport() {
        let failure = CloudKitFailureMapping.failure(
            from: NSError(domain: "anchor.test", code: 1))

        #expect(failure == .transportUnavailable)
    }
}
