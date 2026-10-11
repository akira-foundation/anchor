import AnchorApplication
import AnchorDomain
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Workspace observation publication scheduling", .serialized)
struct WorkspaceObservationPublicationSchedulingTests {
    private let projectID = ProjectID()

    @Test("starting observation returns before a slow publication finishes")
    func startingReturnsBeforeSlowPublication() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let gate = PublicationGate()
        let publisher = RecordingPublicationTarget(gate: gate)
        let coordinator = makePublicationCoordinator(
            projectID: projectID, workspace: workspace, publisher: publisher)
        let probe = StartupProbe()

        let startup = Task {
            try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
            await probe.markReturned()
        }
        let startedCount = await publisher.awaitStartedProjectCount(
            reaching: 1, within: .seconds(10))
        let returnedWhilePublishing = await probe.awaitReturn(within: .seconds(2))
        let isObservingWhilePublishing = await coordinator.isObserving
        await gate.open()
        try await startup.value
        await coordinator.stopObserving()

        #expect(startedCount == 1)
        #expect(returnedWhilePublishing)
        #expect(isObservingWhilePublishing)
    }

    @Test("stopping observation cancels an in-flight publication")
    func stoppingCancelsInFlightPublication() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let gate = PublicationGate()
        let publisher = RecordingPublicationTarget(gate: gate)
        let artifact = try #require(
            Artifact(
                id: .derived(projectID: projectID, provider: .claude, name: "session.json"),
                projectID: projectID, provider: .claude, name: "session.json"))
        let coordinator = makePublicationCoordinator(
            projectID: projectID, workspace: workspace, publisher: publisher,
            artifacts: [artifact])

        let startup = Task {
            try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        }
        _ = await publisher.awaitStartedProjectCount(reaching: 1, within: .seconds(10))
        await coordinator.stopObserving()
        await gate.open()
        try await startup.value
        try await Task.sleep(for: .milliseconds(300))

        #expect(await publisher.publishedArtifactCount == 0)
        #expect(await coordinator.recordedRefusals.allSatisfy { !$0.contains("publishing") })
    }

    @Test("a burst of publication requests coalesces into one more run")
    func burstOfRequestsCoalesces() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let gate = PublicationGate()
        let publisher = RecordingPublicationTarget(gate: gate)
        let coordinator = makePublicationCoordinator(
            projectID: projectID, workspace: workspace, publisher: publisher)

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        _ = await publisher.awaitStartedProjectCount(reaching: 1, within: .seconds(10))
        for _ in 0..<3 {
            await coordinator.requestContextPublication(forWorkspaceAt: workspace)
        }
        await gate.open()
        _ = await publisher.awaitPublishedProjectCount(reaching: 2, within: .seconds(10))
        try await Task.sleep(for: .milliseconds(300))
        await coordinator.stopObserving()

        #expect(await publisher.startedProjectCount == 2)
    }
}
