import AnchorDomain

public protocol ProjectIDStore: Sendable {
    func storeRegisteredProjectID(_ projectID: ProjectID) async throws
    func loadRegisteredProjectIDs() async throws -> [ProjectID]
}
