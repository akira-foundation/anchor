import AnchorDomain

public protocol SearchQueryRunning: Sendable {
    func findMatchingArtifactIDs(forQueryText queryText: String) async throws -> [ArtifactID]
}
