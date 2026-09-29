import AnchorApplication
import AnchorDomain
import Foundation
import Testing

extension MCPStdioFixture {
    func artifactRecord(
        seed: String, projectID: ProjectID, provider: AgentProvider, name: String,
        revisedAt: TimeInterval
    ) throws -> RecordedArtifactRevision {
        let artifact = try #require(
            Artifact(
                id: ArtifactID.derived(fromSeed: seed), projectID: projectID,
                provider: provider, name: name))
        let revision = try #require(
            ArtifactRevision(
                id: RevisionID.derived(fromSeed: "\(seed)-revision"),
                artifactID: artifact.id, parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data(seed.utf8)),
                deviceID: DeviceID.derived(fromSeed: "stdio-device"),
                createdAt: date(revisedAt), retention: artifact.retention))
        return RecordedArtifactRevision(artifact: artifact, revision: revision)
    }

    func knowledgeEntry(
        seed: String, projectID: ProjectID, kind: KnowledgeEntryKind,
        summary: String? = nil, createdAt: TimeInterval,
        source: KnowledgeEntrySource? = nil, supportingMessageIDs: [MessageID] = []
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: KnowledgeEntryID.derived(fromSeed: seed), projectID: projectID, kind: kind,
            summaryText: summary ?? seed,
            source: source ?? .artifact(ArtifactID.derived(fromSeed: "\(seed)-source")),
            sourceContentHash: ContentHash.digest(of: Data(seed.utf8)), origin: .marked,
            supportingMessageIDs: supportingMessageIDs,
            createdAt: date(createdAt))
    }

    func date(_ secondsSinceEpoch: TimeInterval) -> Date {
        Date(timeIntervalSince1970: secondsSinceEpoch)
    }
}

actor FixtureKeyLoadCount {
    private(set) var count = 0

    func recordLoad() { count += 1 }
}

struct FixtureRepositoryRemote: RepositoryRemoteReading {
    func readRepositoryRemote(atDirectory directoryURL: URL) async throws -> RepositoryRemoteOutcome
    {
        .repositoryWithoutRemote
    }
}
