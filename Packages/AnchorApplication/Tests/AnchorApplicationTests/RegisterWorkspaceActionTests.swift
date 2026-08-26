import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

@Suite("Register workspace")
struct RegisterWorkspaceActionTests {
    private let developmentMac = Device(id: DeviceID(), displayName: "Studio", platform: .macOS)
    private let payableDirectory = URL(filePath: "/Developer/payable")

    private func makeAction(
        outcome: RepositoryRemoteOutcome,
        registry: RecordingWorkspaceRegistry
    ) -> RegisterWorkspaceAction {
        RegisterWorkspaceAction(
            remoteReader: StubRepositoryRemoteReader(outcome: outcome),
            identityResolver: RegisteredProjectIdentityResolver(registry: registry),
            workspaceRegistry: registry
        )
    }

    @Test("a repository with a remote is registered against its project")
    func aRepositoryWithARemoteIsRegisteredAgainstItsProject() async throws {
        let registry = RecordingWorkspaceRegistry()
        let remote = try #require(
            CanonicalRepositoryRemote(rawValue: "github.com/akira-io/payable"))
        let action = makeAction(outcome: .remote(remote), registry: registry)

        let outcome = try await action.perform(
            RegisterWorkspaceRequest(device: developmentMac, directoryURL: payableDirectory)
        )

        guard case .registered(let workspace) = outcome else {
            Issue.record("expected a registered workspace, got \(outcome)")
            return
        }
        #expect(workspace.deviceID == developmentMac.id)
        #expect(workspace.localRepositoryURL == payableDirectory)
        #expect(await registry.registeredWorkspaces.count == 1)
    }

    @Test("registering the same directory twice does not duplicate the workspace")
    func registeringTheSameDirectoryTwiceDoesNotDuplicateTheWorkspace() async throws {
        let registry = RecordingWorkspaceRegistry()
        let remote = try #require(
            CanonicalRepositoryRemote(rawValue: "github.com/akira-io/payable"))
        let action = makeAction(outcome: .remote(remote), registry: registry)
        let request = RegisterWorkspaceRequest(
            device: developmentMac, directoryURL: payableDirectory)

        let first = try await action.perform(request)
        let second = try await action.perform(request)

        #expect(first == second)
        #expect(await registry.registeredWorkspaces.count == 1)
    }

    @Test("a device that cannot discover registers nothing")
    func aDeviceThatCannotDiscoverRegistersNothing() async throws {
        let registry = RecordingWorkspaceRegistry()
        let remote = try #require(
            CanonicalRepositoryRemote(rawValue: "github.com/akira-io/payable"))
        let action = makeAction(outcome: .remote(remote), registry: registry)
        let phone = Device(id: DeviceID(), displayName: "iPhone", platform: .iOS)

        let outcome = try await action.perform(
            RegisterWorkspaceRequest(device: phone, directoryURL: payableDirectory)
        )

        #expect(outcome == .deviceCannotDiscover)
        #expect(await registry.registeredWorkspaces.isEmpty)
    }

    @Test("a repository without a remote is reported rather than registered or ignored")
    func aRepositoryWithoutARemoteIsReportedRatherThanRegisteredOrIgnored() async throws {
        let registry = RecordingWorkspaceRegistry()
        let action = makeAction(outcome: .repositoryWithoutRemote, registry: registry)

        let outcome = try await action.perform(
            RegisterWorkspaceRequest(device: developmentMac, directoryURL: payableDirectory)
        )

        #expect(outcome == .repositoryWithoutRemote(payableDirectory))
        #expect(await registry.registeredWorkspaces.isEmpty)
    }

    @Test("a directory that is not a repository is reported")
    func aDirectoryThatIsNotARepositoryIsReported() async throws {
        let registry = RecordingWorkspaceRegistry()
        let action = makeAction(outcome: .notARepository, registry: registry)

        let outcome = try await action.perform(
            RegisterWorkspaceRequest(device: developmentMac, directoryURL: payableDirectory)
        )

        #expect(outcome == .notARepository(payableDirectory))
    }

    @Test("several remotes are handed back for the user to choose")
    func severalRemotesAreHandedBackForTheUserToChoose() async throws {
        let registry = RecordingWorkspaceRegistry()
        let candidates = ["github.com/kid/fork", "github.com/akira-io/original"]
        let action = makeAction(outcome: .severalRemotes(candidates), registry: registry)

        let outcome = try await action.perform(
            RegisterWorkspaceRequest(device: developmentMac, directoryURL: payableDirectory)
        )

        #expect(outcome == .severalRemotes(candidates))
        #expect(await registry.registeredWorkspaces.isEmpty)
    }
}

private struct StubRepositoryRemoteReader: RepositoryRemoteReading {
    let outcome: RepositoryRemoteOutcome

    func readRepositoryRemote(atDirectory directoryURL: URL) async throws -> RepositoryRemoteOutcome
    {
        outcome
    }
}

private actor RecordingWorkspaceRegistry: ProjectIdentityRegistry, WorkspaceRegistry {
    private(set) var registeredProjects: [Project] = []
    private(set) var registeredWorkspaces: [Workspace] = []

    func findProject(
        withRepositoryRemote remote: CanonicalRepositoryRemote
    ) async throws -> Project? {
        registeredProjects.first { $0.canonicalRepositoryRemote == remote }
    }

    func registerProject(_ project: Project) async throws {
        registeredProjects.append(project)
    }

    func findWorkspace(
        forDevice deviceID: DeviceID, atDirectory directoryURL: URL
    ) async throws -> Workspace? {
        registeredWorkspaces.first {
            $0.deviceID == deviceID && $0.localRepositoryURL == directoryURL
        }
    }

    func registerWorkspace(_ workspace: Workspace) async throws {
        registeredWorkspaces.append(workspace)
    }
}
