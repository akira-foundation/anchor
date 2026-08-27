import AnchorDomain
import Foundation

public protocol ArtifactMaterializing: Sendable {
    func materializeArtifact(
        _ artifact: Artifact,
        content: Data,
        atDestination destinationURL: URL
    ) async throws
}
