import AnchorDomain

public protocol ArtifactDiscovering: Sendable {
    func discoverArtifacts(forProject projectID: ProjectID) async throws -> [DiscoveredArtifact]
}
