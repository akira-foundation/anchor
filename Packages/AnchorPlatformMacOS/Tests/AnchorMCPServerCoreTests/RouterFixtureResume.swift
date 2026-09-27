import AnchorApplication
import AnchorDomain
import Foundation

extension RouterFixture {
    func loadConversationEntries(
        inSession sessionID: SessionID, page: ContextPageRequest,
        binding: ContextCursorBinding
    ) async throws -> ContextPage<ConversationEntry> {
        try await loadConversationEntries(
            inSession: sessionID, forProject: project.projectID, page: page,
            binding: binding)
    }

    nonisolated static func resumeArtifact(
        seed: String, projectID: ProjectID, provider: AgentProvider, name: String,
        revisedAt: TimeInterval
    ) -> ArtifactContextRecord {
        let resumeArtifact = Artifact(
            id: ArtifactID.derived(fromSeed: seed), projectID: projectID,
            provider: provider, name: name)!
        let resumeRevision = ArtifactRevision(
            id: RevisionID.derived(fromSeed: "\(seed)-revision"),
            artifactID: resumeArtifact.id, parentRevisionID: nil,
            contentHash: ContentHash.digest(of: Data(seed.utf8)), deviceID: DeviceID(),
            createdAt: Date(timeIntervalSince1970: revisedAt),
            retention: resumeArtifact.retention)!
        return ArtifactContextRecord(artifact: resumeArtifact, latestRevision: resumeRevision)!
    }

    nonisolated static func resumeKnowledge(
        seed: String, projectID: ProjectID, kind: KnowledgeEntryKind, summary: String,
        source: KnowledgeEntrySource, createdAt: TimeInterval
    ) -> ProjectResumeKnowledgeEntry {
        ProjectResumeKnowledgeEntry(
            compacting: KnowledgeEntry(
                id: KnowledgeEntryID.derived(fromSeed: seed), projectID: projectID, kind: kind,
                summaryText: summary, source: source,
                sourceContentHash: ContentHash.digest(of: Data(summary.utf8)), origin: .marked,
                createdAt: Date(timeIntervalSince1970: createdAt)),
            maximumSummaryByteCount: 512)
    }
}
