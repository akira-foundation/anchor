import Foundation

public protocol ArtifactContentReading: Sendable {
    func readContent(
        ofArtifactNamed name: String, inWorkspaceAt workspaceURL: URL
    ) async throws -> Data?
}
