import AnchorDomain
import AnchorProvider
import Foundation
import Testing

@testable import AnchorApplication

@Suite("Recording a workspace change")
struct RecordWorkspaceChangeActionTests {
    private let workspaceURL = URL(filePath: "/Developer/payable")
    private let developmentMac = Device(id: DeviceID(), displayName: "Studio", platform: .macOS)
    private let projectID = ProjectID()

    private func makeAction(
        discovering artifacts: [DiscoveredArtifact],
        content: [String: Data],
        journal: RecordingRevisionJournal
    ) -> RecordWorkspaceChangeAction {
        RecordWorkspaceChangeAction(
            discoverer: StubDiscoverer(artifacts: artifacts),
            contentReader: StubContentReader(contentByName: content),
            revisionRecorder: ArtifactRevisionRecorder(
                journal: journal,
                contentStore: InMemoryArtifactContentStore(),
                deviceID: developmentMac.id
            ),
            operationJournal: AppendOnlySyncOperationJournal()
        )
    }

    private func makeDiscovered(named name: String, content: Data) throws -> DiscoveredArtifact {
        let artifact = try #require(
            Artifact(id: ArtifactID(), projectID: ProjectID(), provider: .superpowers, name: name)
        )

        return DiscoveredArtifact(artifact: artifact, contentHash: ContentHash.digest(of: content))
    }

    @Test("a device that cannot discover records nothing")
    func aDeviceThatCannotDiscoverRecordsNothing() async throws {
        let phone = Device(id: DeviceID(), displayName: "iPhone", platform: .iOS)
        let name = "docs/superpowers/plans/00-indice.md"
        let content = Data("plan".utf8)
        let journal = RecordingRevisionJournal()
        let action = makeAction(
            discovering: [try makeDiscovered(named: name, content: content)],
            content: [name: content], journal: journal
        )

        let outcome = try await action.perform(
            RecordWorkspaceChangeRequest(
                device: phone,
                projectID: projectID,
                change: WorkspaceChange(workspaceURL: workspaceURL, changedPaths: [name])
            )
        )

        #expect(outcome == .deviceCannotDiscover)
        #expect(await journal.recordedRevisions.isEmpty)
    }

    @Test("an artifact the change did not name is still recorded when it differs")
    func anArtifactTheChangeDidNotNameIsStillRecordedWhenItDiffers() async throws {
        let named = "docs/superpowers/plans/00-indice.md"
        let unnamed = "docs/superpowers/specs/01-scaffold.md"
        let journal = RecordingRevisionJournal()
        let action = makeAction(
            discovering: [
                try makeDiscovered(named: named, content: Data("plan".utf8)),
                try makeDiscovered(named: unnamed, content: Data("spec".utf8)),
            ],
            content: [named: Data("plan".utf8), unnamed: Data("spec".utf8)],
            journal: journal
        )

        let outcome = try await action.perform(
            RecordWorkspaceChangeRequest(
                device: developmentMac,
                projectID: projectID,
                change: WorkspaceChange(workspaceURL: workspaceURL, changedPaths: [named])
            )
        )

        #expect(outcome == .recorded(revisionCount: 2))
        #expect(await journal.recordedRevisions.count == 2)
    }

    @Test("a change to content that did not actually change records nothing")
    func aChangeToContentThatDidNotActuallyChangeRecordsNothing() async throws {
        let name = "docs/superpowers/plans/00-indice.md"
        let content = Data("plan".utf8)
        let journal = RecordingRevisionJournal()
        let action = makeAction(
            discovering: [try makeDiscovered(named: name, content: content)],
            content: [name: content], journal: journal
        )
        let request = RecordWorkspaceChangeRequest(
            device: developmentMac,
            projectID: projectID,
            change: WorkspaceChange(workspaceURL: workspaceURL, changedPaths: [name])
        )

        _ = try await action.perform(request)
        let second = try await action.perform(request)

        #expect(second == .recorded(revisionCount: 0))
        #expect(await journal.recordedRevisions.count == 1)
    }
}

private struct StubDiscoverer: ArtifactDiscovering {
    let artifacts: [DiscoveredArtifact]

    func discoverArtifacts(forProject projectID: ProjectID) async throws -> [DiscoveredArtifact] {
        artifacts
    }
}

private struct StubContentReader: ArtifactContentReading {
    let contentByName: [String: Data]

    func readContent(
        ofArtifactNamed name: String, inWorkspaceAt workspaceURL: URL
    ) async throws -> Data? {
        contentByName[name]
    }
}

private actor RecordingRevisionJournal: ArtifactRevisionJournal {
    private(set) var recordedRevisions: [ArtifactRevision] = []

    func latestRevision(forArtifact artifactID: ArtifactID) async throws -> ArtifactRevision? {
        recordedRevisions.last { $0.artifactID == artifactID }
    }

    func revision(withIdentifier revisionID: RevisionID) async throws -> ArtifactRevision? {
        recordedRevisions.first { $0.id == revisionID }
    }

    func recordRevision(_ revision: ArtifactRevision) async throws {
        recordedRevisions.append(revision)
    }
}
