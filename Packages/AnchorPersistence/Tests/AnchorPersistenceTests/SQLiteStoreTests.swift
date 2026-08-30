import AnchorDomain
import AnchorPersistence
import AnchorPersistenceTestSupport
import Foundation
import Testing

@Suite("SQLite stores")
struct SQLiteStoreTests {
    private func makeFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-index-\(UUID().uuidString)/index.sqlite")
    }

    @Test("the project store honours its contract")
    func theProjectStoreHonoursItsContract() async throws {
        try await verifyProjectStoreConformance {
            try! await SQLiteProjectStore(database: try! SQLiteDatabase(fileURL: nil))
        }
    }

    @Test("the workspace store honours its contract")
    func theWorkspaceStoreHonoursItsContract() async throws {
        try await verifyWorkspaceStoreConformance {
            try! await SQLiteWorkspaceStore(database: try! SQLiteDatabase(fileURL: nil))
        }
    }

    @Test("a stored project is still there after reopening the file")
    func aStoredProjectIsStillThereAfterReopeningTheFile() async throws {
        let fileURL = makeFileURL()
        let remote = try #require(CanonicalRepositoryRemote(gitRemote: "github.com/akira/anchor"))
        let project = Project(
            id: ProjectID(), displayName: "Anchor", canonicalRepositoryRemote: remote)

        try await SQLiteProjectStore(database: try SQLiteDatabase(fileURL: fileURL))
            .storeProject(project)

        let reopened = try await SQLiteProjectStore(
            database: try SQLiteDatabase(fileURL: fileURL))

        #expect(try await reopened.loadProject(withIdentifier: project.id) == project)
    }

    @Test("a workspace with no local repository comes back without one")
    func aWorkspaceWithNoLocalRepositoryComesBackWithoutOne() async throws {
        let store = try await SQLiteWorkspaceStore(database: try SQLiteDatabase(fileURL: nil))
        let workspace = Workspace(
            id: WorkspaceID(), projectID: ProjectID(), deviceID: DeviceID(),
            localRepositoryURL: nil
        )

        try await store.storeWorkspace(workspace)

        #expect(try await store.loadWorkspace(withIdentifier: workspace.id) == workspace)
    }

    @Test("a value carrying quotes cannot change the statement")
    func aValueCarryingQuotesCannotChangeTheStatement() async throws {
        let store = try await SQLiteProjectStore(database: try SQLiteDatabase(fileURL: nil))
        let remote = try #require(CanonicalRepositoryRemote(gitRemote: "github.com/akira/anchor"))
        let hostile = Project(
            id: ProjectID(),
            displayName: "'; DROP TABLE projects; --",
            canonicalRepositoryRemote: remote
        )

        try await store.storeProject(hostile)

        #expect(try await store.loadProject(withIdentifier: hostile.id) == hostile)
        #expect(try await store.loadAllProjects().count == 1)
    }
}
