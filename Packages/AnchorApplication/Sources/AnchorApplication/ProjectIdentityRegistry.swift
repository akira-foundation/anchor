import AnchorDomain

public protocol ProjectIdentityRegistry: Sendable {
    func findProject(
        withRepositoryRemote remote: CanonicalRepositoryRemote
    ) async throws -> Project?
    func registerProject(_ project: Project) async throws
}
