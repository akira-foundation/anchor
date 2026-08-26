import AnchorDomain
import Foundation

public struct RegisterWorkspaceRequest: Sendable, Equatable {
    public let device: Device
    public let directoryURL: URL

    public init(device: Device, directoryURL: URL) {
        self.device = device
        self.directoryURL = directoryURL
    }
}

public enum RegisterWorkspaceOutcome: Sendable, Equatable {
    case registered(Workspace)
    case deviceCannotDiscover
    case repositoryWithoutRemote(URL)
    case notARepository(URL)
    case severalRemotes([String])
}

public struct RegisterWorkspaceAction: Action {
    private let remoteReader: any RepositoryRemoteReading
    private let identityResolver: any ProjectIdentityResolving
    private let workspaceRegistry: any WorkspaceRegistry

    public init(
        remoteReader: any RepositoryRemoteReading,
        identityResolver: any ProjectIdentityResolving,
        workspaceRegistry: any WorkspaceRegistry
    ) {
        self.remoteReader = remoteReader
        self.identityResolver = identityResolver
        self.workspaceRegistry = workspaceRegistry
    }

    public func perform(
        _ request: RegisterWorkspaceRequest
    ) async throws -> RegisterWorkspaceOutcome {
        guard request.device.canDiscoverLocalProviders else { return .deviceCannotDiscover }

        switch try await remoteReader.readRepositoryRemote(atDirectory: request.directoryURL) {
        case .notARepository:
            return .notARepository(request.directoryURL)
        case .repositoryWithoutRemote:
            return .repositoryWithoutRemote(request.directoryURL)
        case .severalRemotes(let candidates):
            return .severalRemotes(candidates)
        case .remote(let repositoryRemote):
            return try await registerWorkspace(for: repositoryRemote, request: request)
        }
    }

    private func registerWorkspace(
        for repositoryRemote: CanonicalRepositoryRemote,
        request: RegisterWorkspaceRequest
    ) async throws -> RegisterWorkspaceOutcome {
        let knownWorkspace = try await workspaceRegistry.findWorkspace(
            forDevice: request.device.id,
            atDirectory: request.directoryURL
        )
        if let knownWorkspace { return .registered(knownWorkspace) }

        let projectID = try await identityResolver.resolveProjectIdentity(
            forGitRemote: repositoryRemote.rawValue
        )
        let workspace = Workspace(
            id: WorkspaceID(),
            projectID: projectID,
            deviceID: request.device.id,
            localRepositoryURL: request.directoryURL
        )
        try await workspaceRegistry.registerWorkspace(workspace)

        return .registered(workspace)
    }
}
