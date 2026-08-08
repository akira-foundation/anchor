import AnchorDomain

public protocol WorkspaceStore: Sendable {
    func storeWorkspace(_ workspace: Workspace) async throws
    func loadWorkspace(withIdentifier identifier: WorkspaceID) async throws -> Workspace?
    func loadWorkspaces(forProject projectIdentifier: ProjectID) async throws -> [Workspace]
}
