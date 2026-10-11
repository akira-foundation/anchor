import AnchorApplication
import AnchorDomain
import AnchorStorage
import Foundation

@testable import AnchorPlatformMacOS

struct FixedPublishableContextReader: PublishableProjectContextReading {
    let context: PublishableProjectContext?

    func loadPublishableProjectContext(
        forWorkspaceAt workspaceURL: URL
    ) async throws -> PublishableProjectContext? {
        context
    }
}

struct PublicationRefused: Error {}

actor PublicationGate {
    private var isOpen = false
    private var waitingPublications: [CheckedContinuation<Void, Never>] = []

    init(isOpen: Bool = false) {
        self.isOpen = isOpen
    }

    func pass() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waitingPublications.append($0) }
    }

    func open() {
        isOpen = true
        let released = waitingPublications
        waitingPublications.removeAll()
        for waitingPublication in released { waitingPublication.resume() }
    }
}

actor StartupProbe {
    private(set) var hasReturned = false

    func markReturned() {
        hasReturned = true
    }

    func awaitReturn(within limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while !hasReturned, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        return hasReturned
    }
}

actor RecordingPublicationTarget:
    ProjectDescriptorPublishing, ArtifactDescriptorPublishing, KnowledgeSnapshotPublishing
{
    private let refusingProjects: Bool
    private let gate: PublicationGate
    private(set) var startedProjectCount = 0
    private(set) var publishedProjectCount = 0
    private(set) var publishedArtifactCount = 0

    init(refusingProjects: Bool = false, gate: PublicationGate = PublicationGate(isOpen: true)) {
        self.refusingProjects = refusingProjects
        self.gate = gate
    }

    func publishProjectDescriptor(_ descriptor: PublishedProjectDescriptor) async throws {
        startedProjectCount += 1
        await gate.pass()
        guard !refusingProjects else { throw PublicationRefused() }
        publishedProjectCount += 1
    }

    func awaitPublishedProjectCount(reaching target: Int, within limit: Duration) async -> Int {
        await awaitCount({ $0.publishedProjectCount }, reaching: target, within: limit)
    }

    func awaitStartedProjectCount(reaching target: Int, within limit: Duration) async -> Int {
        await awaitCount({ $0.startedProjectCount }, reaching: target, within: limit)
    }

    func publishArtifactDescriptor(_ artifact: Artifact) async throws {
        publishedArtifactCount += 1
    }

    func publishKnowledgeSnapshot(_ snapshot: KnowledgeSourceSnapshot) async throws {}

    private func awaitCount(
        _ count: (isolated RecordingPublicationTarget) -> Int, reaching target: Int,
        within limit: Duration
    ) async -> Int {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while count(self) < target, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        return count(self)
    }
}

extension WorkspaceObservationCoordinator {
    func awaitRecordedRefusal(
        matching isExpected: @Sendable (String) -> Bool, within limit: Duration
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while !recordedRefusals.contains(where: isExpected), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        return recordedRefusals.contains(where: isExpected)
    }
}

func makePublicationCoordinator(
    projectID: ProjectID, workspace: URL, publisher: RecordingPublicationTarget,
    artifacts: [Artifact] = []
) -> WorkspaceObservationCoordinator {
    let descriptor = PublishedProjectDescriptor(
        projectID: projectID, displayName: "Anchor", canonicalRepositoryRemote: nil)
    let publication = PublishProjectContextAction(
        reader: FixedPublishableContextReader(
            context: PublishableProjectContext(
                project: descriptor, artifacts: artifacts, knowledgeEntries: [],
                knowledgeSources: [])),
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
