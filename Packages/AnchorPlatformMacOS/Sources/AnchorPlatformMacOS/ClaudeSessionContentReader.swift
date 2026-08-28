import AnchorApplication
import AnchorDomain
import Foundation

public struct ClaudeSessionContentReader: ArtifactContentReading {
    private let artifacts: ClaudeSessionArtifacts
    private let projectID: ProjectID

    public init(projectID: ProjectID, artifacts: ClaudeSessionArtifacts = ClaudeSessionArtifacts())
    {
        self.projectID = projectID
        self.artifacts = artifacts
    }

    public func readContent(
        ofArtifactNamed name: String,
        inWorkspaceAt workspaceURL: URL
    ) async throws -> Data? {
        guard name.hasPrefix(SessionArtifact.canonicalPrefix(for: .claude)) else { return nil }

        return artifacts.sessionArtifacts(forProject: projectID, inWorkspaceAt: workspaceURL)
            .first { $0.artifact.name == name }?
            .content
    }
}
