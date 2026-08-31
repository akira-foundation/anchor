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

func cloudKitError(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> CKError {
    CKError(
        _nsError: NSError(domain: CKError.errorDomain, code: code.rawValue, userInfo: userInfo))
}

@Suite("The failure that explains an atomic batch")
struct CloudKitBatchFailureMappingTests {
    @Test("the record that actually failed is preferred over the records it dragged down")
    func recordThatActuallyFailedIsPreferredOverRecordsItDraggedDown() {
        let batch: [any Error] = [
            cloudKitError(.batchRequestFailed),
            cloudKitError(.serverRecordChanged),
        ]

        #expect(
            CloudKitFailureMapping.failure(explaining: batch)
                == .versionTagMismatch(currentVersionTag: nil))
    }

    @Test("the order the batch arrives in does not change the failure the caller sees")
    func orderTheBatchArrivesInDoesNotChangeFailureTheCallerSees() {
        let causes: [any Error] = [
            cloudKitError(.serverRecordChanged),
            cloudKitError(.quotaExceeded),
            cloudKitError(.batchRequestFailed),
        ]

        #expect(
            CloudKitFailureMapping.failure(explaining: causes)
                == CloudKitFailureMapping.failure(explaining: causes.reversed()))
    }

    @Test("a refusal the caller cannot retry away outranks one it can")
    func refusalTheCallerCannotRetryAwayOutranksOneItCan() {
        let batch: [any Error] = [
            cloudKitError(.serverRecordChanged),
            cloudKitError(.quotaExceeded),
        ]

        #expect(CloudKitFailureMapping.failure(explaining: batch) == .quotaExceeded)
    }

    @Test("a batch that only reports the batch itself is still reported")
    func batchThatOnlyReportsBatchItselfIsStillReported() {
        let batch: [any Error] = [cloudKitError(.batchRequestFailed)]

        #expect(CloudKitFailureMapping.failure(explaining: batch) == .transportUnavailable)
    }

    @Test("a batch with nothing wrong in it has no failure to report")
    func batchWithNothingWrongInItHasNoFailureToReport() {
        #expect(CloudKitFailureMapping.failure(explaining: []) == nil)
    }

    @Test("the server record a conflict carries survives the batch it arrived in")
    func serverRecordConflictCarriesSurvivesBatchItArrivedIn() {
        let serverRecord = CKRecord(recordType: "AnchorObject")
        let conflict = cloudKitError(
            .serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: serverRecord])
        let batch: [any Error] = [cloudKitError(.batchRequestFailed), conflict]

        #expect(
            CloudKitFailureMapping.failure(explaining: batch)
                == CloudKitFailureMapping.failure(from: conflict))
    }

    @Test("a partial failure is read for the refusal buried inside it")
    func partialFailureIsReadForRefusalBuriedInsideIt() {
        let inner = cloudKitError(.quotaExceeded)
        let partial = cloudKitError(
            .partialFailure,
            userInfo: [
                CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "object"): inner]
            ])

        #expect(CloudKitFailureMapping.failure(from: partial) == .quotaExceeded)
    }

    @Test("a partial failure that explains nothing is still a transport failure")
    func partialFailureThatExplainsNothingIsStillTransportFailure() {
        #expect(
            CloudKitFailureMapping.failure(from: cloudKitError(.partialFailure))
                == .transportUnavailable)
    }
}

@Suite("The outcome of an atomic modify")
struct CloudKitModifyOutcomeTests {
    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name)
    }

    @Test("a modify where nothing was refused has no failure to report")
    func modifyWhereNothingWasRefusedHasNoFailureToReport() {
        let saves: [CKRecord.ID: Result<CKRecord, any Error>] = [
            recordID("object"): .success(CKRecord(recordType: "AnchorObject"))
        ]
        let deletes: [CKRecord.ID: Result<Void, any Error>] = [recordID("gone"): .success(())]

        #expect(
            CloudKitFailureMapping.failure(explainingSaves: saves, deletes: deletes) == nil)
    }

    @Test("a record the server no longer holds is not a reason to fail a delete")
    func recordServerNoLongerHoldsIsNotReasonToFailDelete() {
        let deletes: [CKRecord.ID: Result<Void, any Error>] = [
            recordID("gone"): .failure(cloudKitError(.unknownItem)),
            recordID("also-gone"): .failure(cloudKitError(.zoneNotFound)),
        ]

        #expect(CloudKitFailureMapping.failure(explainingSaves: [:], deletes: deletes) == nil)
    }

    @Test("a delete the server refused for its own reasons is still reported")
    func deleteServerRefusedForItsOwnReasonsIsStillReported() {
        let deletes: [CKRecord.ID: Result<Void, any Error>] = [
            recordID("object"): .failure(cloudKitError(.notAuthenticated))
        ]

        #expect(
            CloudKitFailureMapping.failure(explainingSaves: [:], deletes: deletes)
                == .accountUnavailable)
    }

    @Test("a refused save is reported even when every delete went through")
    func refusedSaveIsReportedEvenWhenEveryDeleteWentThrough() {
        let saves: [CKRecord.ID: Result<CKRecord, any Error>] = [
            recordID("object"): .failure(cloudKitError(.serverRecordChanged)),
            recordID("log"): .failure(cloudKitError(.batchRequestFailed)),
        ]
        let deletes: [CKRecord.ID: Result<Void, any Error>] = [recordID("gone"): .success(())]

        #expect(
            CloudKitFailureMapping.failure(explainingSaves: saves, deletes: deletes)
                == .versionTagMismatch(currentVersionTag: nil))
    }
}
