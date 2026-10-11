import AnchorApplication
import AnchorDomain
import Foundation
import Testing

@testable import AnchorPersistence

@Suite("SQLite artifact publication listing")
struct SQLiteArtifactPublicationTests {
    @Test("lists every artifact of the project and nothing from another project")
    func listsEveryArtifactOfTheProject() async throws {
        let projectID = ProjectID()
        let store = try await SQLiteArtifactContextStore(database: try SQLiteDatabase(fileURL: nil))
        let owned = try (0..<3).map {
            try indexedRevision(projectID: projectID, name: "doc-\($0).md")
        }
        let foreign = try indexedRevision(projectID: ProjectID(), name: "doc-0.md")

        try await store.indexArtifactRevisions(owned + [foreign])

        let listed = try await store.loadArtifacts(forProject: projectID)
        #expect(listed.map(\.id) == owned.map(\.artifact.id).sorted { $0.rawValue < $1.rawValue })
        #expect(listed.allSatisfy { $0.projectID == projectID })
    }

    @Test("an artifact indexed twice is listed once")
    func artifactIndexedTwiceIsListedOnce() async throws {
        let projectID = ProjectID()
        let store = try await SQLiteArtifactContextStore(database: try SQLiteDatabase(fileURL: nil))
        let firstRevision = try indexedRevision(projectID: projectID, name: "plan.md")
        let secondRevision = try indexedRevision(projectID: projectID, name: "plan.md")

        try await store.indexArtifactRevisions([firstRevision])
        try await store.indexArtifactRevisions([secondRevision])

        let listed = try await store.loadArtifacts(forProject: projectID)
        #expect(listed == [firstRevision.artifact])
    }

    private func indexedRevision(
        projectID: ProjectID, name: String
    ) throws -> RecordedArtifactRevision {
        let artifact = try #require(
            Artifact(
                id: .derived(projectID: projectID, provider: .superpowers, name: name),
                projectID: projectID, provider: .superpowers, name: name))
        let revision = ArtifactRevision(
            id: RevisionID(), artifactID: artifact.id, parentRevisionID: nil,
            contentHash: .digest(of: Data(name.utf8)), deviceID: DeviceID(),
            createdAt: Date(timeIntervalSince1970: 1_000), retention: artifact.retention)
        return RecordedArtifactRevision(artifact: artifact, revision: try #require(revision))
    }
}
