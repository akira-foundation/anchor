import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation

public struct SQLiteContextSearch: ContextSearching, AgentTranscriptIndexing, SessionContextReading
{
    private static let excerptTokenCount = 12
    private static let fullTextMicrosecondMigrationID = "fts-recorded-at-unix-microseconds-v1"

    let database: SQLiteDatabase

    public init(database: SQLiteDatabase) async throws {
        self.database = database
        try await database.execute(
            """
            PRAGMA foreign_keys=ON;
            CREATE TABLE IF NOT EXISTS context_sessions (
                session_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                provider TEXT NOT NULL,
                started_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                parent_session_id TEXT
            );
            CREATE TABLE IF NOT EXISTS context_entries (
                entry_id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                entry_kind TEXT NOT NULL,
                role_or_tool TEXT NOT NULL,
                body TEXT NOT NULL,
                outcome TEXT,
                failed INTEGER,
                recorded_at INTEGER NOT NULL,
                ordering_id TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES context_sessions(session_id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS context_sessions_by_project
                ON context_sessions(project_id, updated_at DESC, session_id);
            CREATE INDEX IF NOT EXISTS context_entries_by_session
                ON context_entries(session_id, recorded_at, ordering_id);
            CREATE TABLE IF NOT EXISTS context_search_migrations (
                migration_id TEXT PRIMARY KEY
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS message_text USING fts5(
                body, session_id UNINDEXED, provider UNINDEXED,
                role UNINDEXED, recorded_at UNINDEXED
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS tool_text USING fts5(
                body, session_id UNINDEXED, provider UNINDEXED,
                tool_name UNINDEXED, recorded_at UNINDEXED
            );
            """
        )
        try await database.withinTransaction { isolatedDatabase in
            try Self.migrateLegacyFullTextTimestamps(in: isolatedDatabase)
        }
    }

    public func indexTranscript(_ transcript: AgentTranscript) async throws {
        try await database.withinTransaction { isolatedDatabase in
            try Self.replaceTranscript(transcript, in: isolatedDatabase)
        }
    }

    public func findContext(matching queryText: String, limit: Int) async throws -> [SearchHit] {
        guard let expression = FullTextQuery.matchExpression(for: queryText) else { return [] }

        let messages = try await hits(
            inTable: "message_text", labelColumn: "role", matching: expression, limit: limit)
        let activities = try await hits(
            inTable: "tool_text", labelColumn: "tool_name", matching: expression, limit: limit)

        return Array(
            (messages + activities).sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    private static func replaceTranscript(
        _ transcript: AgentTranscript, in database: isolated SQLiteDatabase
    ) throws {
        let session = transcript.session

        for table in ["message_text", "tool_text"] {
            try database.run(
                "DELETE FROM \(table) WHERE session_id = ?;", [.text(session.id.rawValue)])
        }
        try database.run(
            "DELETE FROM context_sessions WHERE session_id = ?;", [.text(session.id.rawValue)])
        try database.run(
            """
            INSERT INTO context_sessions (
                session_id, project_id, provider, started_at, updated_at, parent_session_id
            ) VALUES (?, ?, ?, ?, ?, ?);
            """,
            [
                .text(session.id.rawValue), .text(session.projectID.rawValue),
                .text(session.provider.rawValue),
                .integer(SQLiteContextTimestamp.microseconds(sinceUnixEpochFor: session.startedAt)),
                .integer(SQLiteContextTimestamp.microseconds(sinceUnixEpochFor: session.updatedAt)),
                session.parentSessionID.map { .text($0.rawValue) } ?? .null,
            ])

        for entry in transcript.entries {
            try insert(entry, from: session, into: database)
        }
    }

    private static func migrateLegacyFullTextTimestamps(
        in database: isolated SQLiteDatabase
    ) throws {
        let markerRows = try database.run(
            "SELECT migration_id FROM context_search_migrations WHERE migration_id = ? LIMIT 1;",
            [.text(fullTextMicrosecondMigrationID)])
        guard markerRows.isEmpty else { return }

        for table in ["message_text", "tool_text"] {
            try database.run(
                "UPDATE \(table) SET recorded_at = CAST(recorded_at AS INTEGER) * 1000000;")
        }
        try database.run(
            "INSERT INTO context_search_migrations (migration_id) VALUES (?);",
            [.text(fullTextMicrosecondMigrationID)])
    }

    private static func insert(
        _ entry: ConversationEntry,
        from session: AgentSession,
        into database: isolated SQLiteDatabase
    ) throws {
        switch entry {
        case .message(let message):
            try insertMessage(message, from: session, into: database)
        case .toolActivity(let activity):
            try insertToolActivity(activity, from: session, into: database)
        }
    }

    private static func insertMessage(
        _ message: ConversationMessage,
        from session: AgentSession,
        into database: isolated SQLiteDatabase
    ) throws {
        try database.run(
            """
            INSERT INTO context_entries (
                entry_id, session_id, entry_kind, role_or_tool, body, outcome,
                failed, recorded_at, ordering_id
            ) VALUES (?, ?, 'message', ?, ?, NULL, NULL, ?, ?);
            """,
            [
                .text(message.id.rawValue), .text(session.id.rawValue),
                .text(message.role.rawValue), .text(message.content),
                .integer(SQLiteContextTimestamp.microseconds(sinceUnixEpochFor: message.timestamp)),
                .text(message.id.rawValue),
            ])
        try database.run(
            """
            INSERT INTO message_text (body, session_id, provider, role, recorded_at)
            VALUES (?, ?, ?, ?, ?);
            """,
            [
                .text(message.content), .text(session.id.rawValue),
                .text(session.provider.rawValue), .text(message.role.rawValue),
                .integer(SQLiteContextTimestamp.microseconds(sinceUnixEpochFor: message.timestamp)),
            ])
    }

    private static func insertToolActivity(
        _ activity: ToolActivity,
        from session: AgentSession,
        into database: isolated SQLiteDatabase
    ) throws {
        try database.run(
            """
            INSERT INTO context_entries (
                entry_id, session_id, entry_kind, role_or_tool, body, outcome,
                failed, recorded_at, ordering_id
            ) VALUES (?, ?, 'toolActivity', ?, ?, ?, ?, ?, ?);
            """,
            [
                .text(activity.id.rawValue), .text(session.id.rawValue),
                .text(activity.toolName), .text(activity.invocation),
                activity.outcome.map(SQLiteValue.text) ?? .null,
                .integer(activity.failed ? 1 : 0),
                .integer(
                    SQLiteContextTimestamp.microseconds(sinceUnixEpochFor: activity.timestamp)),
                .text(activity.id.rawValue),
            ])
        try database.run(
            """
            INSERT INTO tool_text (body, session_id, provider, tool_name, recorded_at)
            VALUES (?, ?, ?, ?, ?);
            """,
            [
                .text([activity.invocation, activity.outcome ?? ""].joined(separator: "\n")),
                .text(session.id.rawValue), .text(session.provider.rawValue),
                .text(activity.toolName),
                .integer(
                    SQLiteContextTimestamp.microseconds(sinceUnixEpochFor: activity.timestamp)),
            ])
    }

    private func hits(
        inTable table: String, labelColumn: String, matching expression: String, limit: Int
    ) async throws -> [SearchHit] {
        try await database.run(
            """
            SELECT session_id, provider, \(labelColumn) AS label, recorded_at,
                   snippet(\(table), 0, '', '', '...', \(Self.excerptTokenCount)) AS excerpt
            FROM \(table)
            WHERE \(table) MATCH ?
            ORDER BY bm25(\(table))
            LIMIT ?;
            """,
            [.text(expression), .integer(Int64(limit))]
        )
        .compactMap { row in Self.hit(from: row, inTable: table) }
    }

    private static func hit(from row: [String: SQLiteValue], inTable table: String) -> SearchHit? {
        guard let sessionID = row["session_id"]?.text.flatMap(SessionID.init(rawValue:)),
            let provider = row["provider"]?.text.flatMap(AgentProvider.init(rawValue:)),
            let label = row["label"]?.text,
            let recordedAt = row["recorded_at"]?.integer,
            let excerpt = row["excerpt"]?.text,
            let kind = kind(forLabel: label, inTable: table)
        else { return nil }

        return SearchHit(
            sessionID: sessionID,
            provider: provider,
            kind: kind,
            excerpt: excerpt,
            timestamp: SQLiteContextTimestamp.date(fromUnixMicroseconds: recordedAt)
        )
    }

    private static func kind(forLabel label: String, inTable table: String) -> SearchHitKind? {
        guard table == "message_text" else { return .toolActivity(label) }

        return ConversationRole(rawValue: label).map(SearchHitKind.message)
    }
}
