import AnchorDomain
import AnchorPersistence
import Foundation

public struct SQLiteContextSearch: ContextSearching {
    private static let excerptTokenCount = 12

    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) async throws {
        self.database = database
        try await database.execute(
            """
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
    }

    public func indexTranscript(_ transcript: AgentTranscript) async throws {
        let session = transcript.session

        try await forgetSession(session.id)

        for message in transcript.messages {
            try await database.run(
                """
                INSERT INTO message_text (body, session_id, provider, role, recorded_at)
                VALUES (?, ?, ?, ?, ?);
                """,
                [
                    .text(message.content),
                    .text(session.id.rawValue),
                    .text(session.provider.rawValue),
                    .text(message.role.rawValue),
                    .integer(Int64(message.timestamp.timeIntervalSince1970)),
                ]
            )
        }

        for activity in transcript.toolActivities {
            try await database.run(
                """
                INSERT INTO tool_text (body, session_id, provider, tool_name, recorded_at)
                VALUES (?, ?, ?, ?, ?);
                """,
                [
                    .text([activity.invocation, activity.outcome ?? ""].joined(separator: "\n")),
                    .text(session.id.rawValue),
                    .text(session.provider.rawValue),
                    .text(activity.toolName),
                    .integer(Int64(activity.timestamp.timeIntervalSince1970)),
                ]
            )
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

    private func forgetSession(_ sessionID: SessionID) async throws {
        for table in ["message_text", "tool_text"] {
            try await database.run(
                "DELETE FROM \(table) WHERE session_id = ?;", [.text(sessionID.rawValue)])
        }
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
            timestamp: Date(timeIntervalSince1970: TimeInterval(recordedAt))
        )
    }

    private static func kind(forLabel label: String, inTable table: String) -> SearchHitKind? {
        guard table == "message_text" else { return .toolActivity(label) }

        return ConversationRole(rawValue: label).map(SearchHitKind.message)
    }
}
