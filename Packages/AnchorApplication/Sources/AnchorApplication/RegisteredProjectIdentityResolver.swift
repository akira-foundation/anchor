import AnchorDomain

public struct RegisteredProjectIdentityResolver: ProjectIdentityResolving {
    private let registry: any ProjectIdentityRegistry

    public init(registry: any ProjectIdentityRegistry) {
        self.registry = registry
    }

    public func resolveProjectIdentity(forGitRemote gitRemote: String) async throws -> ProjectID {
        guard let repositoryRemote = CanonicalRepositoryRemote(gitRemote: gitRemote) else {
            throw ProjectIdentityFailure.unrecognizedRepositoryRemote(gitRemote)
        }

        if let knownProject = try await registry.findProject(withRepositoryRemote: repositoryRemote)
        {
            return knownProject.id
        }

        let discoveredProject = Project(
            id: ProjectID(),
            displayName: Self.displayName(for: repositoryRemote),
            canonicalRepositoryRemote: repositoryRemote
        )
        try await registry.registerProject(discoveredProject)

        return discoveredProject.id
    }

    private static func displayName(for repositoryRemote: CanonicalRepositoryRemote) -> String {
        String(repositoryRemote.rawValue.split(separator: "/").last ?? "")
    }
}
