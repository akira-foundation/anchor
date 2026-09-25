import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Query-wide context availability")
struct ContextQueryAvailabilityTests {
    @Test(
        "encrypted reads refuse intervening updates even after their marker clears",
        arguments: [true, false])
    func encryptedReadDetectsInterveningUpdate(succeeded: Bool) async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let seeded = try await fixture.seed()
        let writerStatus = ContextReadModelStatusStore(supportDirectoryURL: fixture.support)
        let reader = try await ContextReadModelAssembly.openReader(
            requestedWorkspacePath: fixture.observed.workspaceURL.path(),
            supportDirectoryURL: fixture.support, configurationURL: fixture.configurationURL,
            keyLoader: {
                let update = try await writerStatus.beginUpdate()
                try await writerStatus.completeUpdate(update, succeeded: succeeded)
                return fixture.key
            })

        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await reader.readArtifact.perform(
                try #require(ReadProjectArtifactRequest(artifactID: seeded.artifact.id)))
        }
        let marker = ContextReadModelLocation(supportDirectoryURL: fixture.support).rebuildMarkerURL
        #expect(FileManager.default.fileExists(atPath: marker.path()) == !succeeded)
        let reopened = try await fixture.reader()
        if succeeded {
            #expect(
                try await reopened.currentProject.perform(ProjectContextRequest()).projectID
                    == fixture.observed.projectID)
        } else {
            await #expect(throws: ContextQueryFailure.contextUnavailable) {
                try await reopened.currentProject.perform(ProjectContextRequest())
            }
        }
    }
}
