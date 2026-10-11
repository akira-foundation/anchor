import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import Foundation
import Testing

@Suite("SQLite knowledge atomic recording")
struct SQLiteKnowledgeAtomicRecordingTests {
    private let projectID = ProjectID()

    @Test("a failed insert rolls back the supersede so the previous entries stay current")
    func failedInsertKeepsPreviousEntriesCurrent() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let store = try await SQLiteKnowledgeStore(database: database)
        let source = KnowledgeEntrySource.session(SessionID())
        try await store.recordEntries(
            [entry("kept", source, 10)], supersedingEntriesFrom: source)
        try await database.execute(
            """
            CREATE TRIGGER refuse_poisoned_entry BEFORE INSERT ON knowledge_entries
            WHEN NEW.summary_text = 'poisoned'
            BEGIN SELECT RAISE(ABORT, 'poisoned entry'); END;
            """)

        await #expect(throws: (any Error).self) {
            try await store.recordEntries(
                [entry("replacement", source, 20), entry("poisoned", source, 30)],
                supersedingEntriesFrom: source)
        }

        let listing = try await store.loadPublishableKnowledge(forProject: projectID)
        #expect(listing.currentEntries.map(\.summaryText) == ["kept"])
        #expect(listing.sources == [source])
    }

    private func entry(
        _ summary: String, _ source: KnowledgeEntrySource, _ createdAt: TimeInterval
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: KnowledgeEntryID(), projectID: projectID, kind: .decision,
            summaryText: summary, source: source,
            sourceContentHash: .digest(of: Data(summary.utf8)),
            createdAt: Date(timeIntervalSince1970: createdAt))
    }
}
