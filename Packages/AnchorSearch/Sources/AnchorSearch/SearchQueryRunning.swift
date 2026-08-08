import AnchorDomain

public protocol SearchQueryRunning: Sendable {
    func findMatchingArtifactIdentifiers(forQueryText queryText: String) async throws -> [ArtifactIdentifier]
}
