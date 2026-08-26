import AnchorDomain
import Foundation

public protocol WorkspaceRegistry: Sendable {
    func findWorkspace(
        forDevice deviceID: DeviceID, atDirectory directoryURL: URL
    ) async throws -> Workspace?
    func registerWorkspace(_ workspace: Workspace) async throws
}
