import AnchorDomain
import Testing

@testable import AnchorApplication

@Suite("Registered project identity resolver")
struct RegisteredProjectIdentityResolverTests {
    @Test("the same remote resolves to the same identity across separate calls")
    func theSameRemoteResolvesToTheSameIdentityAcrossSeparateCalls() async throws {
        let registry = RecordingProjectIdentityRegistry()
        let resolver = RegisteredProjectIdentityResolver(registry: registry)

        let first = try await resolver.resolveProjectIdentity(
            forGitRemote: "https://github.com/akira-io/payable")
        let second = try await resolver.resolveProjectIdentity(
            forGitRemote: "https://github.com/akira-io/payable")

        #expect(first == second)
        #expect(await registry.registrationCount == 1)
    }

    @Test("the three remote forms of one repository reach one identity")
    func theThreeRemoteFormsOfOneRepositoryReachOneIdentity() async throws {
        let registry = RecordingProjectIdentityRegistry()
        let resolver = RegisteredProjectIdentityResolver(registry: registry)

        let fromSSH = try await resolver.resolveProjectIdentity(
            forGitRemote: "git@github.com:akira-io/payable.git")
        let fromHTTPS = try await resolver.resolveProjectIdentity(
            forGitRemote: "https://github.com/akira-io/payable.git")
        let bare = try await resolver.resolveProjectIdentity(
            forGitRemote: "https://github.com/akira-io/payable")

        #expect(fromSSH == fromHTTPS)
        #expect(fromHTTPS == bare)
        #expect(await registry.registrationCount == 1)
    }

    @Test("two repositories keep separate identities")
    func twoRepositoriesKeepSeparateIdentities() async throws {
        let registry = RecordingProjectIdentityRegistry()
        let resolver = RegisteredProjectIdentityResolver(registry: registry)

        let payable = try await resolver.resolveProjectIdentity(
            forGitRemote: "https://github.com/akira-io/payable")
        let anchor = try await resolver.resolveProjectIdentity(
            forGitRemote: "https://github.com/akira-io/anchor")

        #expect(payable != anchor)
        #expect(await registry.registrationCount == 2)
    }

    @Test("an identity already registered is reused rather than replaced")
    func anIdentityAlreadyRegisteredIsReusedRatherThanReplaced() async throws {
        let remote = try #require(
            CanonicalRepositoryRemote(rawValue: "github.com/akira-io/payable"))
        let knownProject = Project(
            id: ProjectID(), displayName: "Payable", canonicalRepositoryRemote: remote)
        let registry = RecordingProjectIdentityRegistry(knownProjects: [knownProject])
        let resolver = RegisteredProjectIdentityResolver(registry: registry)

        let resolved = try await resolver.resolveProjectIdentity(
            forGitRemote: "git@github.com:akira-io/payable.git")

        #expect(resolved == knownProject.id)
        #expect(await registry.registrationCount == 0)
    }

    @Test("a newly registered project is named after the last path segment")
    func aNewlyRegisteredProjectIsNamedAfterTheLastPathSegment() async throws {
        let registry = RecordingProjectIdentityRegistry()
        let resolver = RegisteredProjectIdentityResolver(registry: registry)

        _ = try await resolver.resolveProjectIdentity(
            forGitRemote: "https://gitlab.example.com/team/subgroup/service.git"
        )

        #expect(await registry.registeredProjects.first?.displayName == "service")
    }

    @Test("a remote without a canonical form is refused and registers nothing")
    func aRemoteWithoutACanonicalFormIsRefusedAndRegistersNothing() async throws {
        let registry = RecordingProjectIdentityRegistry()
        let resolver = RegisteredProjectIdentityResolver(registry: registry)

        await #expect(throws: ProjectIdentityFailure.unrecognizedRepositoryRemote("payable")) {
            try await resolver.resolveProjectIdentity(forGitRemote: "payable")
        }
        #expect(await registry.registrationCount == 0)
    }
}

private actor RecordingProjectIdentityRegistry: ProjectIdentityRegistry {
    private(set) var registeredProjects: [Project]
    private(set) var registrationCount = 0

    init(knownProjects: [Project] = []) {
        self.registeredProjects = knownProjects
    }

    func findProject(
        withRepositoryRemote remote: CanonicalRepositoryRemote
    ) async throws -> Project? {
        registeredProjects.first { $0.canonicalRepositoryRemote == remote }
    }

    func registerProject(_ project: Project) async throws {
        registeredProjects.append(project)
        registrationCount += 1
    }
}
