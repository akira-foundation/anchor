import AnchorDomain

public protocol ProjectIdentifierStore: Sendable {
    func storeRegisteredProjectIdentifier(_ projectIdentifier: ProjectIdentifier) async throws
    func loadRegisteredProjectIdentifiers() async throws -> [ProjectIdentifier]
}
