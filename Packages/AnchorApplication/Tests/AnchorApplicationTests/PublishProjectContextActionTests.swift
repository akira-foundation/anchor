import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

@Suite("Publish project context action")
struct PublishProjectContextActionTests {
    private let projectID = ProjectID()
    private let workspaceURL = URL(filePath: "/Users/dev/anchor")

    @Test("publishes the project, every artifact and one snapshot per knowledge source")
    func publishesProjectArtifactsAndKnowledge() async throws {
        let artifact = try #require(makeArtifact(name: "session-a.json"))
        let sessionSource = KnowledgeEntrySource.session(SessionID())
        let entry = makeEntry(source: sessionSource, summary: "Use SQLite", state: .current)
        let publisher = RecordingContextPublisher()
        let action = makeAction(
            context: PublishableProjectContext(
                project: descriptor, artifacts: [artifact], knowledgeEntries: [entry]),
            publisher: publisher)

        let report = try await action.perform(
            PublishProjectContextRequest(workspaceURL: workspaceURL))

        #expect(report.refusals.isEmpty)
        #expect(await publisher.projects == [descriptor])
        #expect(await publisher.artifacts == [artifact])
        #expect(await publisher.snapshots.map(\.entries) == [[entry]])
    }

    @Test("superseded entries are never published")
    func supersededEntriesAreNeverPublished() async throws {
        let source = KnowledgeEntrySource.session(SessionID())
        let current = makeEntry(source: source, summary: "Current", state: .current)
        let superseded = makeEntry(source: source, summary: "Old", state: .superseded)
        let publisher = RecordingContextPublisher()
        let action = makeAction(
            context: PublishableProjectContext(
                project: descriptor, artifacts: [], knowledgeEntries: [superseded, current]),
            publisher: publisher)

        _ = try await action.perform(PublishProjectContextRequest(workspaceURL: workspaceURL))

        #expect(await publisher.snapshots.flatMap(\.entries) == [current])
    }

    @Test("a source with only superseded entries publishes an empty snapshot")
    func sourceWithOnlySupersededEntriesPublishesEmptySnapshot() async throws {
        let source = KnowledgeEntrySource.artifact(ArtifactID())
        let superseded = makeEntry(source: source, summary: "Gone", state: .superseded)
        let publisher = RecordingContextPublisher()
        let action = makeAction(
            context: PublishableProjectContext(
                project: descriptor, artifacts: [], knowledgeEntries: [superseded]),
            publisher: publisher)

        _ = try await action.perform(PublishProjectContextRequest(workspaceURL: workspaceURL))

        let snapshots = await publisher.snapshots
        #expect(snapshots.map(\.source) == [source])
        #expect(snapshots.first?.entries == [])
    }

    @Test("one failed publication does not stop the others")
    func oneFailedPublicationDoesNotStopTheOthers() async throws {
        let first = try #require(makeArtifact(name: "first.md"))
        let second = try #require(makeArtifact(name: "second.md"))
        let publisher = RecordingContextPublisher(failingArtifactName: "first.md")
        let action = makeAction(
            context: PublishableProjectContext(
                project: descriptor, artifacts: [first, second], knowledgeEntries: []),
            publisher: publisher)

        let report = try await action.perform(
            PublishProjectContextRequest(workspaceURL: workspaceURL))

        #expect(await publisher.artifacts == [second])
        #expect(report.refusals.count == 1)
        #expect(report.refusals.first?.hasPrefix("publishing artifact first.md:") == true)
    }

    @Test("an unknown workspace publishes nothing")
    func unknownWorkspacePublishesNothing() async throws {
        let publisher = RecordingContextPublisher()
        let action = makeAction(context: nil, publisher: publisher)

        let report = try await action.perform(
            PublishProjectContextRequest(workspaceURL: workspaceURL))

        #expect(report.refusals.isEmpty)
        #expect(await publisher.projects.isEmpty)
    }

    @Test("a snapshot rejects entries from another source or project")
    func snapshotRejectsForeignEntries() {
        let source = KnowledgeEntrySource.session(SessionID())
        let foreign = makeEntry(source: .session(SessionID()), summary: "Other", state: .current)

        #expect(
            KnowledgeSourceSnapshot(projectID: projectID, source: source, entries: [foreign]) == nil
        )
    }

    private var descriptor: PublishedProjectDescriptor {
        PublishedProjectDescriptor(
            projectID: projectID, displayName: "Anchor",
            canonicalRepositoryRemote: CanonicalRepositoryRemote(
                rawValue: "github.com/akira-foundation/anchor"))
    }

    private func makeAction(
        context: PublishableProjectContext?, publisher: RecordingContextPublisher
    ) -> PublishProjectContextAction {
        PublishProjectContextAction(
            reader: FixedPublishableContextReader(context: context),
            projects: publisher, artifacts: publisher, knowledge: publisher)
    }

    private func makeArtifact(name: String) -> Artifact? {
        Artifact(
            id: .derived(projectID: projectID, provider: .claude, name: name),
            projectID: projectID, provider: .claude, name: name)
    }

    private func makeEntry(
        source: KnowledgeEntrySource, summary: String, state: KnowledgeEntryState
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: KnowledgeEntryID(), projectID: projectID, kind: .decision, summaryText: summary,
            source: source, sourceContentHash: .digest(of: Data(summary.utf8)), state: state,
            createdAt: Date(timeIntervalSince1970: 1_000))
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

private actor RecordingContextPublisher:
    ProjectDescriptorPublishing, ArtifactDescriptorPublishing, KnowledgeSnapshotPublishing
{
    private let failingArtifactName: String?
    private(set) var projects: [PublishedProjectDescriptor] = []
    private(set) var artifacts: [Artifact] = []
    private(set) var snapshots: [KnowledgeSourceSnapshot] = []

    init(failingArtifactName: String? = nil) {
        self.failingArtifactName = failingArtifactName
    }

    func publishProjectDescriptor(_ descriptor: PublishedProjectDescriptor) async throws {
        projects.append(descriptor)
    }

    func publishArtifactDescriptor(_ artifact: Artifact) async throws {
        guard artifact.name != failingArtifactName else { throw PublicationRefused() }
        artifacts.append(artifact)
    }

    func publishKnowledgeSnapshot(_ snapshot: KnowledgeSourceSnapshot) async throws {
        snapshots.append(snapshot)
    }
}
