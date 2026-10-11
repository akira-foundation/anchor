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
        let publishedCount = await publisher.awaitPublishedProjectCount(
            reaching: 1, within: .seconds(10))
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
        _ = await publisher.awaitPublishedProjectCount(reaching: 1, within: .seconds(10))
        try Data("after".utf8)
            .write(to: workspace.appending(path: "docs/superpowers/plans/00-indice.md"))
        let publishedCount = await publisher.awaitPublishedProjectCount(
            reaching: 2, within: .seconds(10))
        await coordinator.stopObserving()

        #expect(publishedCount == 2)
    }
}
