import AnchorDomain

public struct DiscoveredArtifact: Sendable, Hashable {
    public let artifact: Artifact
    public let contentHash: ContentHash

    public init(artifact: Artifact, contentHash: ContentHash) {
        self.artifact = artifact
        self.contentHash = contentHash
    }
}
