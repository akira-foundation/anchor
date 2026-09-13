import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorKnowledge

@Suite("Persisting evidence for knowledge")
struct KnowledgeEvidencePersistenceTests {
    private let projectID = ProjectID()
    private let artifactID = ArtifactID()

    @Test("the knowledge store retains supporting message identifiers")
    func knowledgeStoreRetainsSupportingMessageIdentifiers() async throws {
        let messageIDs = [MessageID(), MessageID()]
        let store = try await makeStore()
        let supportedEntry = entry(
            "Keep inference opt-in", digestOf: "one", origin: .inferred,
            supportingMessageIDs: messageIDs)

        try await store.recordEntries(
            [supportedEntry], supersedingEntriesFrom: supportedEntry.source)

        let storedEntry = try #require(
            try await store.entries(
                forProject: supportedEntry.projectID, includingSuperseded: false
            )
            .first)
        #expect(storedEntry.supportingMessageIDs == messageIDs)
    }

    @Test("legacy inferred knowledge without evidence is superseded")
    func legacyInferredKnowledgeWithoutEvidenceIsSuperseded() async throws {
        let database = try await makeLegacyDatabase()
        let store = try await SQLiteKnowledgeStore(database: database)

        let currentEntries = try await store.entries(
            forProject: projectID, includingSuperseded: false)
        let allEntries = try await store.entries(forProject: projectID, includingSuperseded: true)

        #expect(currentEntries.map(\.origin) == [.marked])
        #expect(allEntries.first(where: { $0.origin == .inferred })?.state == .superseded)
        #expect(allEntries.first(where: { $0.origin == .marked })?.state == .current)
    }

    @Test("malformed supporting message identifiers surface a store decoding failure")
    func malformedSupportingMessageIdentifiersSurfaceAStoreDecodingFailure() async throws {
        let database = try await makeLegacyDatabase()
        let store = try await SQLiteKnowledgeStore(database: database)
        let markedRow = try #require(
            try await database.run(
                "SELECT id FROM knowledge_entries WHERE origin = ?;",
                [.text(KnowledgeEntryOrigin.marked.rawValue)]
            ).first)
        let markedEntryID = try #require(
            markedRow["id"]?.text.flatMap(KnowledgeEntryID.init(rawValue:)))
        try await database.run(
            "UPDATE knowledge_entries SET supporting_message_ids = ? WHERE id = ?;",
            [.text("not JSON"), .text(markedEntryID.rawValue)])

        do {
            _ = try await store.entries(forProject: projectID, includingSuperseded: false)
            Issue.record("expected malformed evidence to stop knowledge decoding")
        } catch let failure as SQLiteKnowledgeStoreFailure {
            #expect(failure == .invalidSupportingMessageIdentifiers(markedEntryID))
        }
    }

    private func makeStore() async throws -> SQLiteKnowledgeStore {
        try await SQLiteKnowledgeStore(database: try SQLiteDatabase(fileURL: nil))
    }

    private func makeLegacyDatabase() async throws -> SQLiteDatabase {
        let database = try SQLiteDatabase(fileURL: nil)
        try await database.execute(
            """
            CREATE TABLE knowledge_entries (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                summary_text TEXT NOT NULL,
                source TEXT NOT NULL,
                source_content_hash TEXT NOT NULL,
                origin TEXT NOT NULL DEFAULT 'classified',
                state TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            """)

        let encodedSource = String(
            decoding: try JSONEncoder().encode(KnowledgeEntrySource.artifact(artifactID)),
            as: UTF8.self)
        for origin in [KnowledgeEntryOrigin.inferred, .marked] {
            try await database.run(
                """
                INSERT INTO knowledge_entries (
                    id, project_id, kind, summary_text, source, source_content_hash,
                    origin, state, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                [
                    .text(KnowledgeEntryID().rawValue),
                    .text(projectID.rawValue),
                    .text(KnowledgeEntryKind.decision.rawValue),
                    .text("keep the journal local"),
                    .text(encodedSource),
                    .text(ContentHash.digest(of: Data("one".utf8)).rawValue),
                    .text(origin.rawValue),
                    .text(KnowledgeEntryState.current.rawValue),
                    .integer(0),
                ])
        }

        return database
    }

    private func entry(
        _ summaryText: String,
        digestOf sourceText: String,
        origin: KnowledgeEntryOrigin,
        supportingMessageIDs: [MessageID] = []
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: KnowledgeEntryID(),
            projectID: projectID,
            kind: .decision,
            summaryText: summaryText,
            source: .artifact(artifactID),
            sourceContentHash: ContentHash.digest(of: Data(sourceText.utf8)),
            origin: origin,
            supportingMessageIDs: supportingMessageIDs,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
