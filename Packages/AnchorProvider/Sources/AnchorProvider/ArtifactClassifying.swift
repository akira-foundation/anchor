import AnchorDomain

public protocol ArtifactClassifying: Sendable {
    func classifyKnowledgeEntries(
        in discoveredArtifact: DiscoveredArtifact
    ) async throws -> [KnowledgeEntry]
}
