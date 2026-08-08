import AnchorDomain
import Testing

@testable import AnchorPersistence

private actor InMemoryProjectStore: ProjectStore {
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

@Suite("ProjectStore contract")
struct ProjectStoreContractTests {
    private func makeProject(displayName: String) -> Project {
        Project(
            id: ProjectID(),
            displayName: displayName,
            canonicalRepositoryRemote: "github.com/akira-foundation/anchor"
        )
    }

    @Test("a stored project is returned by its identifier")
    func storedProjectIsReturnedByItsIdentifier() async throws {
        let projectStore = InMemoryProjectStore()
        let expectedProject = makeProject(displayName: "Anchor")

        try await projectStore.storeProject(expectedProject)

        #expect(
            try await projectStore.loadProject(withIdentifier: expectedProject.id)
                == expectedProject)
    }

    @Test("an unknown identifier returns no project")
    func unknownIdentifierReturnsNoProject() async throws {
        let projectStore = InMemoryProjectStore()

        #expect(try await projectStore.loadProject(withIdentifier: ProjectID()) == nil)
    }

    @Test("storing a project again replaces it rather than duplicating it")
    func storingAProjectAgainReplacesItRatherThanDuplicatingIt() async throws {
        let projectStore = InMemoryProjectStore()
        let originalProject = makeProject(displayName: "Anchor")
        let renamedProject = Project(
            id: originalProject.id,
            displayName: "Anchor Context Layer",
            canonicalRepositoryRemote: originalProject.canonicalRepositoryRemote
        )

        try await projectStore.storeProject(originalProject)
        try await projectStore.storeProject(renamedProject)

        #expect(try await projectStore.loadAllProjects() == [renamedProject])
    }
}
