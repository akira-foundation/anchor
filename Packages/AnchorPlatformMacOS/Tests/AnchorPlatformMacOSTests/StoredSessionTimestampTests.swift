import AnchorApplication
import AnchorDomain
import AnchorPersistence
import AnchorSearch
import AnchorStorage
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Recorded session timestamp authority")
struct StoredSessionTimestampTests {
    @Test("live knowledge recording uses the authoritative revision timestamp")
    func knowledgeUsesRevisionTimestamp() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let canonical = try #require(
            SessionArtifact.make(from: fixture.transcript, forProject: fixture.observed.projectID))
        let revision = ArtifactRevision(
            id: RevisionID(), artifactID: canonical.artifact.id, parentRevisionID: nil,
            contentHash: ContentHash.digest(of: canonical.content), deviceID: DeviceID(),
            createdAt: Date(timeIntervalSince1970: 123))!
        let content = StoredArtifactContentStore(storage: InMemoryStorageProvider())
        try await content.storeContent(canonical.content, forRevision: revision.id)
        let knowledge = KnowledgeTimestampSpy()
        let recorder = StoredSessionContextRecorder(
            contentStore: content,
            action: RecordSessionContextAction(
                index: try await SQLiteContextSearch(database: SQLiteDatabase(fileURL: nil)),
                knowledge: knowledge))
        let refusals = await recorder.recordSessionContext(
            in: [RecordedArtifactRevision(artifact: canonical.artifact, revision: revision)],
            at: Date(timeIntervalSince1970: 999))
        #expect(refusals.isEmpty)
        #expect(await knowledge.recordedAt == Date(timeIntervalSince1970: 123))
    }
}

private actor KnowledgeTimestampSpy: AgentSessionKnowledgeRecording {
    var recordedAt: Date?
    func recordKnowledge(
        fromText text: String, forProject projectID: ProjectID, source: KnowledgeEntrySource,
        sourceContentHash: ContentHash, at instant: Date
    ) async throws {
        recordedAt = instant
    }
}
