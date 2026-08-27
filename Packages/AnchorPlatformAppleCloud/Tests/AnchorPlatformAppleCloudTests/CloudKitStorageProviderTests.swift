import AnchorDomain
import AnchorPlatformAppleCloud
import AnchorStorage
import AnchorStorageTestSupport
import Foundation
import Testing

@Suite("CloudKit storage provider")
struct CloudKitStorageProviderTests {
    @Test("it honours the storage provider contract")
    func itHonoursTheStorageProviderContract() async throws {
        try await verifyStorageProviderConformance {
            CloudKitStorageProvider(database: InMemoryCloudRecordDatabase())
        }
    }
}

@Suite("CloudKit storage provider behaviour")
struct CloudKitStorageProviderBehaviourTests {
    private func key(_ rawValue: String) throws -> StorageKey {
        try #require(StorageKey(rawValue: rawValue))
    }

    @Test("deleting a key that was never written announces nothing")
    func deletingAKeyThatWasNeverWrittenAnnouncesNothing() async throws {
        let database = InMemoryCloudRecordDatabase()
        let provider = CloudKitStorageProvider(database: database)

        try await provider.deleteObject(for: try key("projects/anchor/index"))

        #expect(try await database.logEntries(after: nil).entries.isEmpty)
    }

    @Test("a cursor from one provider resumes in the next one over the same account")
    func cursorFromOneProviderResumesInTheNextOneOverTheSameAccount() async throws {
        let database = InMemoryCloudRecordDatabase()
        let first = CloudKitStorageProvider(database: database)

        try await first.putObject(
            StorageObject(key: try key("projects/anchor/index"), contents: Data("first".utf8)),
            precondition: .none
        )
        try await first.putObject(
            StorageObject(key: try key("devices/laptop"), contents: Data("second".utf8)),
            precondition: .none
        )

        var cursor: StorageCursor?

        for try await change in first.observeChanges(after: nil) {
            cursor = change.cursor
            break
        }

        let resumed = CloudKitStorageProvider(database: database)
        var resumedKeys: [String] = []

        for try await change in resumed.observeChanges(after: cursor) {
            resumedKeys.append(change.key.rawValue)
            break
        }

        #expect(resumedKeys == ["devices/laptop"])
    }

    @Test(
        "a condition that no retry can fix is not reported as a transport problem",
        arguments: [
            (CloudDatabaseFailure.accountUnavailable, StorageFailure.accountUnavailable),
            (CloudDatabaseFailure.quotaExceeded, StorageFailure.quotaExceeded),
        ]
    )
    func conditionThatNoRetryCanFixIsNotReportedAsATransportProblem(
        raised: CloudDatabaseFailure, expected: StorageFailure
    ) async throws {
        let provider = CloudKitStorageProvider(
            database: FailingCloudRecordDatabase(raising: raised))

        await #expect(throws: expected) {
            try await provider.putObject(
                StorageObject(key: try self.key("projects/anchor/index"), contents: Data()),
                precondition: .none
            )
        }
    }
}
