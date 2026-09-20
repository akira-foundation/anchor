import AnchorApplication
import AnchorDomain
import Foundation
import Testing

@testable import AnchorPersistence

@Suite("Malformed project context")
struct SQLiteMalformedProjectTests {
    @Test("a malformed stored project does not masquerade as missing context")
    func malformedProjectFailsExplicitly() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let catalog = try await SQLiteArtifactContextStore(database: database)
        let workspace = URL(filePath: "/test-workspace")
        try await catalog.recordProjectContext(
            ProjectContext(
                projectID: ProjectID(), displayName: "test",
                canonicalRepositoryRemote: nil, workspaceURL: workspace))
        try await database.run("UPDATE context_projects SET project_id = 'malformed';")
        await #expect(throws: (any Error).self) {
            try await catalog.loadProjectContext(forWorkspaceAt: workspace)
        }
    }
}
