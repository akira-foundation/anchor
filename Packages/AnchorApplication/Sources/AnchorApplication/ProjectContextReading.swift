import AnchorDomain
import Foundation

public struct ProjectContext: Sendable, Hashable {
    public let projectID: ProjectID
    public let displayName: String
    public let canonicalRepositoryRemote: CanonicalRepositoryRemote?
    public let workspaceURL: URL

    public init(
        projectID: ProjectID,
        displayName: String,
        canonicalRepositoryRemote: CanonicalRepositoryRemote?,
        workspaceURL: URL
    ) {
        self.projectID = projectID
        self.displayName = displayName
        self.canonicalRepositoryRemote = canonicalRepositoryRemote
        self.workspaceURL = workspaceURL
    }
}

public protocol ProjectContextReading: Sendable {
    func loadProjectContext(forWorkspaceAt workspaceURL: URL) async throws -> ProjectContext?
}
