import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorSearch

@Suite("SQLite context search migrations")
struct SQLiteContextSearchMigrationTests {
    @Test("legacy FTS seconds migrate once and retain order beside new microseconds")
    func legacySecondTimestampsMigrateExactlyOnce() async throws {
        let databaseFileURL = makeDatabaseFileURL()
        defer {
            try? FileManager.default.removeItem(at: databaseFileURL.deletingLastPathComponent())
        }
        try await seedLegacyFullTextRows(at: databaseFileURL)

        let firstOpenSearch = try await SQLiteContextSearch(
            database: try SQLiteDatabase(fileURL: databaseFileURL))
        let newSession = makeSession(identifierSuffix: 603, updatedAt: 400.25)
        try await firstOpenSearch.indexTranscript(
            AgentTranscript(
                session: newSession,
                entries: [
                    makeMessage(
                        sessionID: newSession.id,
                        identifierSuffix: 604,
                        text: "migration-order-token new",
                        role: .assistant,
                        at: 400.25)
                ]))

        let firstOpenHits = try await firstOpenSearch.findContext(
            matching: "migration-order-token", limit: 10)
        #expect(
            firstOpenHits.map(\.kind) == [
                .message(.assistant), .toolActivity("LegacyShell"), .message(.user),
            ])
        expectTimestamps(firstOpenHits, equal: [400.25, 300, 200])

        let secondOpenSearch = try await SQLiteContextSearch(
            database: try SQLiteDatabase(fileURL: databaseFileURL))
        let secondOpenHits = try await secondOpenSearch.findContext(
            matching: "migration-order-token", limit: 10)

        #expect(secondOpenHits.map(\.kind) == firstOpenHits.map(\.kind))
        expectTimestamps(secondOpenHits, equal: [400.25, 300, 200])
    }

    private func seedLegacyFullTextRows(at databaseFileURL: URL) async throws {
        let database = try SQLiteDatabase(fileURL: databaseFileURL)
        try await database.execute(
            """
            CREATE VIRTUAL TABLE message_text USING fts5(
                body, session_id UNINDEXED, provider UNINDEXED,
                role UNINDEXED, recorded_at UNINDEXED
            );
            CREATE VIRTUAL TABLE tool_text USING fts5(
                body, session_id UNINDEXED, provider UNINDEXED,
                tool_name UNINDEXED, recorded_at UNINDEXED
            );
            """)
        try await database.run(
            """
            INSERT INTO message_text (body, session_id, provider, role, recorded_at)
            VALUES (?, ?, ?, ?, ?);
            """,
            [
                .text("migration-order-token old-message"), .text(sessionID(601).rawValue),
                .text(AgentProvider.claude.rawValue), .text(ConversationRole.user.rawValue),
                .integer(200),
            ])
        try await database.run(
            """
            INSERT INTO tool_text (body, session_id, provider, tool_name, recorded_at)
            VALUES (?, ?, ?, ?, ?);
            """,
            [
                .text("migration-order-token old-tool"), .text(sessionID(602).rawValue),
                .text(AgentProvider.claude.rawValue), .text("LegacyShell"), .integer(300),
            ])
    }

    private func expectTimestamps(_ hits: [SearchHit], equal expectedSeconds: [TimeInterval]) {
        #expect(hits.count == expectedSeconds.count)
        for (hit, expectedTimestamp) in zip(hits, expectedSeconds) {
            #expect(abs(hit.timestamp.timeIntervalSince1970 - expectedTimestamp) < 0.000001)
        }
    }
}
