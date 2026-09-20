import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import AnchorSearch
import AnchorStorage
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Which recorded revisions reach the index")
struct StoredSessionContextRecorderTests {
    private let projectID = ProjectID()
    private let recordedAt = Date(timeIntervalSince1970: 1_000)

    private func makeTranscript(_ sessionID: SessionID, _ content: String) -> AgentTranscript {
        AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .claude,
                startedAt: recordedAt, updatedAt: recordedAt),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID(), sessionID: sessionID, role: .user,
                        content: content, timestamp: recordedAt))
            ]
        )
    }

    private func encode(_ transcript: AgentTranscript) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(transcript.inConversationOrder)
    }

    private func makeArtifact(named name: String, provider: AgentProvider) throws -> Artifact {
        try #require(
            Artifact(id: ArtifactID(), projectID: projectID, provider: provider, name: name))
    }

    private func makeRecordedRevision(
        for artifact: Artifact,
        revisionID: RevisionID,
        content: Data
    ) throws -> RecordedArtifactRevision {
        RecordedArtifactRevision(
            artifact: artifact,
            revision: try #require(
                ArtifactRevision(
                    id: revisionID,
                    artifactID: artifact.id,
                    parentRevisionID: nil,
                    contentHash: ContentHash.digest(of: content),
                    deviceID: DeviceID(),
                    createdAt: recordedAt,
                    retention: artifact.retention
                ))
        )
    }

    @Test("only the sessions among the recorded revisions are indexed")
    func onlySessionsAmongRecordedRevisionsAreIndexed() async throws {
        let storage = InMemoryStorageProvider()
        let contentStore = StoredArtifactContentStore(storage: storage)
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let sessionID = SessionID()

        let sessionRevisionID = RevisionID()
        let planRevisionID = RevisionID()
        let sessionContent = try encode(makeTranscript(sessionID, "the checkpoint stays honest"))
        let planContent = Data("a plan, not a transcript".utf8)
        let planArtifact = try makeArtifact(
            named: "docs/superpowers/plans/00.md", provider: .superpowers)
        let sessionArtifact = try makeArtifact(
            named: AgentSessionArtifactNaming.name(forSession: sessionID, provider: .claude),
            provider: .claude)
        try await contentStore.storeContent(sessionContent, forRevision: sessionRevisionID)
        try await contentStore.storeContent(planContent, forRevision: planRevisionID)

        let recorder = StoredSessionContextRecorder(
            contentStore: contentStore,
            action: RecordSessionContextAction(
                index: SearchedTranscriptIndex(search: search),
                knowledge: ExtractedSessionKnowledge(
                    extractor: MarkedKnowledgeExtractor(),
                    store: try await SQLiteKnowledgeStore(database: database)
                )
            )
        )

        let refusals = await recorder.recordSessionContext(
            in: [
                try makeRecordedRevision(
                    for: planArtifact, revisionID: planRevisionID, content: planContent),
                try makeRecordedRevision(
                    for: sessionArtifact, revisionID: sessionRevisionID, content: sessionContent),
            ],
            at: recordedAt
        )

        let hits = try await search.findContext(matching: "checkpoint", limit: 10)

        #expect(refusals.isEmpty)
        #expect(hits.map(\.sessionID) == [sessionID])
    }

    @Test("a session nobody can read does not stop the sessions after it")
    func sessionNobodyCanReadDoesNotStopSessionsAfterIt() async throws {
        let storage = InMemoryStorageProvider()
        let contentStore = StoredArtifactContentStore(storage: storage)
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let goodSessionID = SessionID()

        let brokenRevisionID = RevisionID()
        let goodRevisionID = RevisionID()
        let broken = Data("this was never a transcript".utf8)
        let good = try encode(makeTranscript(goodSessionID, "the checkpoint stays honest"))
        let brokenArtifact = try makeArtifact(
            named: AgentSessionArtifactNaming.name(forSession: SessionID(), provider: .claude),
            provider: .claude)
        let goodArtifact = try makeArtifact(
            named: AgentSessionArtifactNaming.name(forSession: goodSessionID, provider: .claude),
            provider: .claude)
        try await contentStore.storeContent(broken, forRevision: brokenRevisionID)
        try await contentStore.storeContent(good, forRevision: goodRevisionID)

        let recorder = StoredSessionContextRecorder(
            contentStore: contentStore,
            action: RecordSessionContextAction(
                index: SearchedTranscriptIndex(search: search),
                knowledge: ExtractedSessionKnowledge(
                    extractor: MarkedKnowledgeExtractor(),
                    store: try await SQLiteKnowledgeStore(database: database)
                )
            )
        )

        let refusals = await recorder.recordSessionContext(
            in: [
                try makeRecordedRevision(
                    for: brokenArtifact, revisionID: brokenRevisionID, content: broken),
                try makeRecordedRevision(
                    for: goodArtifact, revisionID: goodRevisionID, content: good),
            ],
            at: recordedAt
        )

        let hits = try await search.findContext(matching: "checkpoint", limit: 10)

        #expect(refusals.count == 1)
        #expect(refusals.first?.description.contains("contentIsNotATranscript") == true)
        #expect(hits.map(\.sessionID) == [goodSessionID])
    }

    @Test("a session whose content is gone records an indexing refusal")
    func sessionWhoseContentIsGoneRecordsAnIndexingRefusal() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let recorder = StoredSessionContextRecorder(
            contentStore: StoredArtifactContentStore(storage: InMemoryStorageProvider()),
            action: RecordSessionContextAction(
                index: SearchedTranscriptIndex(
                    search: try await SQLiteContextSearch(database: database)),
                knowledge: ExtractedSessionKnowledge(
                    extractor: MarkedKnowledgeExtractor(),
                    store: try await SQLiteKnowledgeStore(database: database)
                )
            )
        )
        let artifact = try makeArtifact(
            named: AgentSessionArtifactNaming.name(forSession: SessionID(), provider: .claude),
            provider: .claude)
        let emptyContent = Data()

        let refusals = await recorder.recordSessionContext(
            in: [
                try makeRecordedRevision(
                    for: artifact, revisionID: RevisionID(), content: emptyContent)
            ],
            at: recordedAt
        )

        #expect(refusals.count == 1)
        #expect(refusals.first?.artifactName == artifact.name)
        #expect(refusals.first?.description.contains("entityNotFound") == true)
    }
}
