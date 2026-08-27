import AnchorDomain
import AnchorProvider
import Foundation

extension SuperpowersArtifactProvider: ArtifactClassifying {
    public func classifyKnowledgeEntries(
        in discoveredArtifact: DiscoveredArtifact
    ) async throws -> [KnowledgeEntry] {
        guard let firstLine = firstNonEmptyLine(of: discoveredArtifact.artifact) else { return [] }

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

    private func firstNonEmptyLine(of artifact: Artifact) -> String? {
        guard let content = readContent(of: artifact) else { return nil }

        return String(decoding: content, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
