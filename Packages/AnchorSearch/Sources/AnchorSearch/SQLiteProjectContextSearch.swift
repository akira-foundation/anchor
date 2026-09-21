import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation

extension SQLiteContextSearch {
    public func searchContext(
        forProject projectID: ProjectID, matching text: String, page: ContextPageRequest,
        binding: ContextCursorBinding
    )
        async throws -> ContextPage<ProjectContextSearchHit>
    {
        let position = try SQLiteContextCursor.decode(
            page.cursor, operation: .searchProject,
            scopeBinding: projectID.rawValue, filterBinding: text, binding: binding)
        guard let expression = FullTextQuery.matchExpression(for: text) else {
            return ContextPage(records: [], nextCursor: nil)
        }
        return try await database.withinTransaction { isolatedDatabase in
            try Self.validateSearchCandidates(
                matching: expression, forProject: projectID, in: isolatedDatabase)
            return try Self.searchPage(
                forProject: projectID, text: text, expression: expression, page: page,
                position: position, binding: binding, in: isolatedDatabase)
        }
    }

    private static func searchPage(
        forProject projectID: ProjectID, text: String, expression: String,
        page: ContextPageRequest, position: SQLiteContextCursorPosition?,
        binding: ContextCursorBinding,
        in database: isolated SQLiteDatabase
    ) throws -> ContextPage<ProjectContextSearchHit> {
        let messageQuery = Self.searchStatement(
            table: "message_text", kind: "message", label: "role",
            body: "e.body")
        let activityQuery = Self.searchStatement(
            table: "tool_text", kind: "toolActivity", label: "tool_name",
            body: "e.body || char(10) || COALESCE(e.outcome, '')")
        var statement =
            "WITH hits AS (\(messageQuery) UNION ALL \(activityQuery)) SELECT * FROM hits WHERE 1 = 1"
        var parameters: [SQLiteValue] = [
            .text(expression), .text(projectID.rawValue), .text(expression),
            .text(projectID.rawValue),
        ]
        if let position {
            statement += " AND (recorded_at < ? OR (recorded_at = ? AND entry_id > ?))"
            parameters += [
                .integer(position.timestamp), .integer(position.timestamp),
                .text(position.identifier),
            ]
        }
        statement += " ORDER BY recorded_at DESC, entry_id ASC LIMIT ?;"
        parameters.append(.integer(Int64(page.limit) + 1))
        let rows = try database.run(statement, parameters)
        let decoded = try rows.map(Self.projectSearchHit)
        let records = Array(decoded.prefix(page.limit))
        var nextCursor: ContextPageCursor?
        if rows.count > page.limit, let last = rows.prefix(page.limit).last,
            let timestamp = last["recorded_at"]?.integer, let identifier = last["entry_id"]?.text
        {
            nextCursor = try SQLiteContextCursor.encode(
                operation: .searchProject, scopeBinding: projectID.rawValue,
                filterBinding: text,
                binding: binding,
                position: SQLiteContextCursorPosition(timestamp: timestamp, identifier: identifier))
        }
        return ContextPage(records: records, nextCursor: nextCursor)
    }

    private static func searchStatement(
        table: String, kind: String, label: String, body: String
    ) -> String {
        """
        SELECT DISTINCT e.*, s.provider,
            snippet(\(table), 0, '', '', '...', 12) AS excerpt
        FROM \(table) JOIN context_entries e ON e.session_id = \(table).session_id
            AND e.entry_kind = '\(kind)' AND \(body) = \(table).body
            AND e.role_or_tool = \(table).\(label) AND e.recorded_at = \(table).recorded_at
        JOIN context_sessions s ON s.session_id = e.session_id
        WHERE \(table) MATCH ? AND s.project_id = ?
        """
    }

    private static func projectSearchHit(
        from row: [String: SQLiteValue]
    ) throws -> ProjectContextSearchHit {
        _ = try conversationEntry(from: row)
        guard let sessionID = row["session_id"]?.text.flatMap(SessionID.init(rawValue:)),
            let provider = row["provider"]?.text.flatMap(AgentProvider.init(rawValue:)),
            let label = row["role_or_tool"]?.text, let kind = row["entry_kind"]?.text,
            let timestamp = row["recorded_at"]?.integer, let excerpt = row["excerpt"]?.text
        else { throw SQLiteContextReadFailure.malformedEntry }
        let hitKind: ProjectContextSearchHitKind
        switch kind {
        case "message":
            guard let role = ConversationRole(rawValue: label) else {
                throw SQLiteContextReadFailure.malformedEntry
            }
            hitKind = .message(role)
        case "toolActivity": hitKind = .toolActivity(label)
        default: throw SQLiteContextReadFailure.malformedEntry
        }
        return ProjectContextSearchHit(
            sessionID: sessionID, provider: provider, kind: hitKind,
            excerpt: excerpt,
            timestamp: SQLiteContextTimestamp.date(fromUnixMicroseconds: timestamp))
    }
}
