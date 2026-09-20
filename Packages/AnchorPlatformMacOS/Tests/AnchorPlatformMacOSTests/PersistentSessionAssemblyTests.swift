import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Persistent session composition")
struct PersistentSessionAssemblyTests {
    @Test("session context and artifact catalog use the supplied writer database")
    func sessionContextUsesSuppliedDatabase() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let context = try await ContextEngineAssembly.makeSessionContext(
            storage: fixture.storage(),
            database: writer.database)
        try await context.transcripts.replaceTranscripts(
            [fixture.transcript], forProject: fixture.observed.projectID)
        let artifact = Artifact(
            id: ArtifactID(), projectID: fixture.observed.projectID, provider: .codex,
            name: "saved.md")!
        let revision = ArtifactRevision(
            id: RevisionID(), artifactID: artifact.id, parentRevisionID: nil,
            contentHash: ContentHash.digest(of: Data("saved".utf8)), deviceID: DeviceID(),
            createdAt: Date(timeIntervalSince1970: 55))!
        try await context.artifactIndex.indexArtifactRevisions([
            RecordedArtifactRevision(artifact: artifact, revision: revision)
        ])
        let reopened = try await ContextEngineAssembly.makeSessionContext(
            storage: fixture.storage(),
            database: SQLiteDatabase(fileURL: writer.databaseURL))
        #expect(
            try await reopened.sessions.loadSession(withIdentifier: fixture.transcript.session.id)?
                .session == fixture.transcript.session)
        #expect(
            try await writer.artifacts.loadArtifact(withIdentifier: artifact.id)?.latestRevision?
                .createdAt == revision.createdAt)
    }
}
