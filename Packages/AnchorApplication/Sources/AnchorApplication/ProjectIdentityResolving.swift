import AnchorDomain

public protocol ProjectIdentityResolving: Sendable {
    func resolveProjectIdentity(forGitRemote gitRemote: String) async throws -> ProjectID
}

public enum ProjectIdentityFailure: Error, Sendable, Equatable {
    case unrecognizedRepositoryRemote(String)
}
