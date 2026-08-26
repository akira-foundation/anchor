import AnchorDomain
import Testing

@testable import AnchorApplication

@Suite("Project identity resolving contract")
struct ProjectIdentityResolvingContractTests {
    @Test("the same repository reached by different remote forms resolves to one identity")
    func theSameRepositoryReachedByDifferentRemoteFormsResolvesToOneIdentity() async throws {
        let resolver = InMemoryProjectIdentityResolver()

        let fromSSH = try await resolver.resolveProjectIdentity(
            forGitRemote: "git@github.com:akira-io/payable.git")
        let fromHTTPS = try await resolver.resolveProjectIdentity(
            forGitRemote: "https://github.com/akira-io/payable")

        #expect(fromSSH == fromHTTPS)
    }

    @Test("two different repositories resolve to different identities")
    func twoDifferentRepositoriesResolveToDifferentIdentities() async throws {
        let resolver = InMemoryProjectIdentityResolver()

        let payable = try await resolver.resolveProjectIdentity(
            forGitRemote: "https://github.com/akira-io/payable")
        let anchor = try await resolver.resolveProjectIdentity(
            forGitRemote: "https://github.com/akira-io/anchor")

        #expect(payable != anchor)
    }

    @Test("a remote without a canonical form is rejected rather than given an identity")
    func aRemoteWithoutACanonicalFormIsRejected() async {
        let resolver = InMemoryProjectIdentityResolver()

        await #expect(throws: ProjectIdentityFailure.unrecognizedRepositoryRemote("payable")) {
            try await resolver.resolveProjectIdentity(forGitRemote: "payable")
        }
    }
}

private actor InMemoryProjectIdentityResolver: ProjectIdentityResolving {
    private var identitiesByRemote: [CanonicalRepositoryRemote: ProjectID] = [:]

    func resolveProjectIdentity(forGitRemote gitRemote: String) async throws -> ProjectID {
        guard let repositoryRemote = CanonicalRepositoryRemote(gitRemote: gitRemote) else {
            throw ProjectIdentityFailure.unrecognizedRepositoryRemote(gitRemote)
        }

        if let knownIdentity = identitiesByRemote[repositoryRemote] {
            return knownIdentity
        }

        let freshIdentity = ProjectID()
        identitiesByRemote[repositoryRemote] = freshIdentity

        return freshIdentity
    }
}
