import AnchorApplication
import AnchorDomain
import AnchorProvider
import Foundation

public struct CodexSessionProvider: ArtifactDiscovering {
    private let workspaceURL: URL
    private let artifacts: CodexSessionArtifacts

    public init(workspaceURL: URL, artifacts: CodexSessionArtifacts = CodexSessionArtifacts()) {
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

public struct CodexSessionContentReader: ArtifactContentReading {
    private let artifacts: CodexSessionArtifacts
    private let projectID: ProjectID

    public init(projectID: ProjectID, artifacts: CodexSessionArtifacts = CodexSessionArtifacts()) {
        self.projectID = projectID
        self.artifacts = artifacts
    }

    public func readContent(
        ofArtifactNamed name: String,
        inWorkspaceAt workspaceURL: URL
    ) async throws -> Data? {
        guard name.hasPrefix(SessionArtifact.canonicalPrefix(for: .codex)) else { return nil }

        return artifacts.sessionArtifacts(forProject: projectID, inWorkspaceAt: workspaceURL)
            .first { $0.artifact.name == name }?
            .content
    }
}
