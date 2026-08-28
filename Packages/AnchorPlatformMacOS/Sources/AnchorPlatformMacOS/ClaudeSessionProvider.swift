import AnchorDomain
import AnchorProvider
import Foundation

public struct ClaudeSessionProvider: ArtifactDiscovering {
    private let workspaceURL: URL
    private let artifacts: ClaudeSessionArtifacts

    public init(workspaceURL: URL, artifacts: ClaudeSessionArtifacts = ClaudeSessionArtifacts()) {
        self.workspaceURL = workspaceURL
        self.artifacts = artifacts
    }

    public func discoverArtifacts(
        forProject projectID: ProjectID
    ) async throws -> [DiscoveredArtifact] {
        artifacts.sessionArtifacts(forProject: projectID, inWorkspaceAt: workspaceURL)
            .map {
                DiscoveredArtifact(
                    artifact: $0.artifact, contentHash: ContentHash.digest(of: $0.content))
            }
    }
}
