import AnchorDomain
import AnchorPersistence
import AnchorPersistenceTestSupport
import Testing

actor InMemoryProjectStore: ProjectStore {
    private var projectsByIdentifier: [ProjectID: Project] = [:]

    func storeProject(_ project: Project) async throws {
        projectsByIdentifier[project.id] = project
    }

    func loadProject(withIdentifier identifier: ProjectID) async throws -> Project? {
        projectsByIdentifier[identifier]
    }

    func loadAllProjects() async throws -> [Project] {
        projectsByIdentifier.values.sorted { $0.displayName < $1.displayName }
    }
}

actor InMemoryWorkspaceStore: WorkspaceStore {
    private var workspacesByIdentifier: [WorkspaceID: Workspace] = [:]

    func storeWorkspace(_ workspace: Workspace) async throws {
        workspacesByIdentifier[workspace.id] = workspace
    }

    func loadWorkspace(withIdentifier identifier: WorkspaceID) async throws -> Workspace? {
        workspacesByIdentifier[identifier]
    }

    func loadWorkspaces(forProject projectIdentifier: ProjectID) async throws -> [Workspace] {
        workspacesByIdentifier.values
            .filter { $0.projectID == projectIdentifier }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }
}

@Suite("In memory stores conform to the persistence contracts")
struct InMemoryStoreTests {
    @Test("the in memory project store satisfies every contract expectation")
    func inMemoryProjectStoreSatisfiesEveryContractExpectation() async throws {
        try await verifyProjectStoreConformance { InMemoryProjectStore() }
    }

    @Test("the in memory workspace store satisfies every contract expectation")
    func inMemoryWorkspaceStoreSatisfiesEveryContractExpectation() async throws {
        try await verifyWorkspaceStoreConformance { InMemoryWorkspaceStore() }
    }
}
