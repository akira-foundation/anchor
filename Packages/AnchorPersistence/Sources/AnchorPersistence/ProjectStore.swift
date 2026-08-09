import AnchorDomain

public protocol ProjectStore: Sendable {
    func storeProject(_ project: Project) async throws
    func loadProject(withIdentifier identifier: ProjectID) async throws -> Project?
    func loadAllProjects() async throws -> [Project]
}
