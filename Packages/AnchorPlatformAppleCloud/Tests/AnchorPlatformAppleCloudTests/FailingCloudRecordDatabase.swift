import AnchorPlatformAppleCloud
import AnchorStorage
import Foundation

struct FailingCloudRecordDatabase: CloudRecordDatabase {
    let raised: CloudDatabaseFailure

    init(raising raised: CloudDatabaseFailure) {
        self.raised = raised
    }

    func snapshot(named name: String) async throws(CloudDatabaseFailure) -> CloudRecordSnapshot? {
        throw raised
    }

    func objectSnapshots() async throws(CloudDatabaseFailure) -> [CloudRecordSnapshot] {
        throw raised
    }

    @discardableResult
    func save(
        _ draft: CloudRecordDraft,
        precondition: StorageWritePrecondition,
        recording entry: CloudLogEntry
    ) async throws(CloudDatabaseFailure) -> CloudRecordSnapshot {
        throw raised
    }

    func remove(
        recordNamed name: String, recording entry: CloudLogEntry
    ) async throws(CloudDatabaseFailure) {
        throw raised
    }

    func logEntries(after token: Data?) async throws(CloudDatabaseFailure) -> CloudLogPage {
        throw raised
    }
}
