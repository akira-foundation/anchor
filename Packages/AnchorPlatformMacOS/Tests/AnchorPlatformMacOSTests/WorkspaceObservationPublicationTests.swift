import AnchorApplication
import AnchorDomain
import AnchorStorage
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
        let coordinator = makeCoordinator(workspace: workspace, publisher: publisher)

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        await coordinator.stopObserving()

        #expect(await publisher.publishedProjectCount == 1)
    }

    @Test("a refused publication is remembered as a refusal")
    func refusedPublicationIsRemembered() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let publisher = RecordingPublicationTarget(refusingProjects: true)
        let coordinator = makeCoordinator(workspace: workspace, publisher: publisher)

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        await coordinator.stopObserving()

        let refusals = await coordinator.recordedRefusals
        #expect(refusals.contains { $0.hasPrefix("publishing project Anchor:") })
    }

    @Test("an observed edit publishes the project context again")
    func observedEditPublishesContextAgain() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "before"])
        let publisher = RecordingPublicationTarget()
        let coordinator = makeCoordinator(workspace: workspace, publisher: publisher)

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        try Data("after".utf8)
            .write(to: workspace.appending(path: "docs/superpowers/plans/00-indice.md"))
        let publishedCount = await publisher.awaitPublishedProjectCount(
            reaching: 2, within: .seconds(10))
        await coordinator.stopObserving()

        #expect(publishedCount == 2)
    }

    private func makeCoordinator(
        workspace: URL, publisher: RecordingPublicationTarget
    ) -> WorkspaceObservationCoordinator {
        let descriptor = PublishedProjectDescriptor(
            projectID: projectID, displayName: "Anchor", canonicalRepositoryRemote: nil)
        let publication = PublishProjectContextAction(
            reader: FixedPublishableContextReader(
                context: PublishableProjectContext(
                    project: descriptor, artifacts: [], knowledgeEntries: [])),
            projects: publisher, artifacts: publisher, knowledge: publisher)

        return WorkspaceObservationCoordinatorTests().makeCoordinator(
            device: Device(id: DeviceID(), displayName: "Studio", platform: .macOS),
            storage: InMemoryStorageProvider(),
            checkpointStore: ObservationCheckpointStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appending(path: "anchor-publication-\(UUID().uuidString)/checkpoints.json")),
            workspaceURL: workspace,
            contextPublication: publication
        ).0
    }
}

private struct FixedPublishableContextReader: PublishableProjectContextReading {
    let context: PublishableProjectContext?

    func loadPublishableProjectContext(
        forWorkspaceAt workspaceURL: URL
    ) async throws -> PublishableProjectContext? {
        context
    }
}

private struct PublicationRefused: Error {}

private actor RecordingPublicationTarget:
    ProjectDescriptorPublishing, ArtifactDescriptorPublishing, KnowledgeSnapshotPublishing
{
    private let refusingProjects: Bool
    private(set) var publishedProjectCount = 0

    init(refusingProjects: Bool = false) {
        self.refusingProjects = refusingProjects
    }

    func publishProjectDescriptor(_ descriptor: PublishedProjectDescriptor) async throws {
        guard !refusingProjects else { throw PublicationRefused() }
        publishedProjectCount += 1
    }

    func awaitPublishedProjectCount(reaching target: Int, within limit: Duration) async -> Int {
        let deadline = ContinuousClock.now.advanced(by: limit)

        while publishedProjectCount < target, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        return publishedProjectCount
    }

    func publishArtifactDescriptor(_ artifact: Artifact) async throws {}

    func publishKnowledgeSnapshot(_ snapshot: KnowledgeSourceSnapshot) async throws {}
}
