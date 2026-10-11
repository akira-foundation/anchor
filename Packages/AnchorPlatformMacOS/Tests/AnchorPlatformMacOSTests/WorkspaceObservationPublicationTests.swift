import AnchorApplication
import AnchorDomain
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Workspace observation publication", .serialized)
struct WorkspaceObservationPublicationTests {
    private let projectID = ProjectID()

    @Test("starting observation publishes the project context once")
    func startingObservationPublishesContext() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let publisher = RecordingPublicationTarget()
        let coordinator = makePublicationCoordinator(
            projectID: projectID, workspace: workspace, publisher: publisher)

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        await coordinator.awaitPublicationSettled()
        let publishedCount = await publisher.publishedProjectCount
        await coordinator.stopObserving()

        #expect(publishedCount == 1)
    }

    @Test("a refused publication is remembered as a refusal")
    func refusedPublicationIsRemembered() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let publisher = RecordingPublicationTarget(refusingProjects: true)
        let coordinator = makePublicationCoordinator(
            projectID: projectID, workspace: workspace, publisher: publisher)

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        let remembered = await coordinator.awaitRecordedRefusal(
            matching: { $0.hasPrefix("publishing project Anchor:") }, within: .seconds(10))
        await coordinator.stopObserving()

        #expect(remembered)
    }

    @Test("an observed edit publishes the project context again")
    func observedEditPublishesContextAgain() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "before"])
        let publisher = RecordingPublicationTarget()
        let coordinator = makePublicationCoordinator(
            projectID: projectID, workspace: workspace, publisher: publisher)

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        await coordinator.awaitPublicationSettled()
        let publishedAtStartup = await publisher.publishedProjectCount
        try Data("after".utf8)
            .write(to: workspace.appending(path: "docs/superpowers/plans/00-indice.md"))
        _ = await publisher.awaitPublishedProjectCount(reaching: 2, within: .seconds(10))
        await coordinator.awaitPublicationSettled()
        let publishedAfterEdit = await publisher.publishedProjectCount
        await coordinator.stopObserving()

        #expect(publishedAtStartup == 1)
        #expect(publishedAfterEdit == 2)
    }
}
