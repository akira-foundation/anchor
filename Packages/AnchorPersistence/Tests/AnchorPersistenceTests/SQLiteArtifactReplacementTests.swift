import AnchorApplication
import AnchorDomain
import Foundation
import Testing

@testable import AnchorPersistence

@Suite("Artifact catalog replacement")
struct SQLiteArtifactReplacementTests {
    @Test("replacement removes stale artifacts preserves other projects and rejects foreign inputs")
    func replacementValidatesAndRemovesStaleArtifacts() async throws {
        let store = try await SQLiteArtifactContextStore(database: try SQLiteDatabase(fileURL: nil))
        let projectID = ProjectID()
        let stale = makeRevision(forProject: projectID)
        let replacement = makeRevision(forProject: projectID)
        let foreign = makeRevision(forProject: ProjectID())
        try await store.indexArtifactRevisions([stale, foreign])
        try await store.replaceArtifactRevisions([replacement], forProject: projectID)
        try await store.replaceArtifactRevisions([replacement], forProject: projectID)
        #expect(try await store.loadArtifact(withIdentifier: stale.artifact.id) == nil)
        #expect(
            try await store.loadArtifact(withIdentifier: replacement.artifact.id)?.latestRevision?
                .id == replacement.revision.id)
        await #expect(throws: ContextReplacementFailure.projectMismatch) {
            try await store.replaceArtifactRevisions([foreign], forProject: projectID)
        }
        #expect(try await store.loadArtifact(withIdentifier: foreign.artifact.id) != nil)
        #expect(try await store.loadArtifact(withIdentifier: replacement.artifact.id) != nil)
    }

    private func makeRevision(forProject projectID: ProjectID) -> RecordedArtifactRevision {
        let artifact = Artifact(
            id: ArtifactID(), projectID: projectID, provider: .codex, name: "plan.md")!
        let revision = ArtifactRevision(
            id: RevisionID(), artifactID: artifact.id, parentRevisionID: nil,
            contentHash: ContentHash.digest(of: Data("plan".utf8)), deviceID: DeviceID(),
            createdAt: Date(timeIntervalSince1970: 10))!
        return RecordedArtifactRevision(artifact: artifact, revision: revision)
    }
}
