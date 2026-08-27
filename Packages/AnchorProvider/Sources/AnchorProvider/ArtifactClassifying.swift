import AnchorDomain
import Foundation

public protocol ArtifactClassifying: Sendable {
    func classifyKnowledgeEntries(
        in discoveredArtifact: DiscoveredArtifact,
        content: Data
    ) async throws -> [KnowledgeEntry]
}
