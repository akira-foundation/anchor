import AnchorDomain
import AnchorProvider
import Foundation

extension SuperpowersArtifactProvider: ArtifactClassifying {
    public func classifyKnowledgeEntries(
        in discoveredArtifact: DiscoveredArtifact,
        content: Data
    ) async throws -> [KnowledgeEntry] {
        guard let firstLine = ArtifactSummaryLine.firstNonEmptyLine(of: content) else { return [] }

        return [
            KnowledgeEntry(
                id: KnowledgeEntryID(),
                projectID: discoveredArtifact.artifact.projectID,
                kind: knowledgeKind(for: discoveredArtifact.artifact),
                summaryText: firstLine,
                source: .artifact(discoveredArtifact.artifact.id),
                createdAt: Date()
            )
        ]
    }

    private func knowledgeKind(for artifact: Artifact) -> KnowledgeEntryKind {
        let canonicalPath = artifact.name.split(separator: "/").dropLast().joined(separator: "/")

        return SuperpowersArtifactLocation.location(forCanonicalPath: canonicalPath)?
            .vouchedKnowledgeKind ?? .summary
    }
}
