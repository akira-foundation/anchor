import AnchorPlatformAppleCloud
import AnchorStorageTestSupport
import CloudKit
import Foundation
import Testing

private let liveContainerIdentifier = ProcessInfo.processInfo.environment[
    "ANCHOR_ICLOUD_CONTAINER"]

@Suite(
    "CloudKit database against a real iCloud account",
    .enabled(if: liveContainerIdentifier != nil)
)
struct CloudKitDatabaseLiveTests {
    @Test("it honours the storage provider contract against iCloud")
    func itHonoursTheStorageProviderContractAgainstICloud() async throws {
        let identifier = try #require(liveContainerIdentifier)
        let zoneName = "AnchorConformance-\(UUID().uuidString)"

        try await verifyStorageProviderConformance {
            CloudKitStorageProvider(
                database: CloudKitDatabase(
                    container: CKContainer(identifier: identifier), zoneName: zoneName)
            )
        }
    }
}
