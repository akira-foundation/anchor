import AnchorDomain
import AnchorPersistence

extension SQLiteContextSearch {
    static func validateSearchCandidates(
        matching expression: String, forProject projectID: ProjectID,
        in database: isolated SQLiteDatabase
    ) throws {
        try validateCandidates(
            table: "message_text", kind: "message", label: "role",
            body: "e.body", expression: expression, projectID: projectID, in: database)
        try validateCandidates(
            table: "tool_text", kind: "toolActivity", label: "tool_name",
            body: "e.body || char(10) || COALESCE(e.outcome, '')",
            expression: expression, projectID: projectID, in: database)
    }

    private static func validateCandidates(
        table: String, kind: String, label: String, body: String,
        expression: String, projectID: ProjectID, in database: isolated SQLiteDatabase
    ) throws {
        let corrupt = try database.run(
            """
            WITH candidates AS (
                SELECT \(table).body, \(table).session_id, \(table).provider,
                    \(table).\(label) AS label, \(table).recorded_at, COUNT(*) AS occurrences
                FROM \(table) LEFT JOIN context_sessions s ON s.session_id = \(table).session_id
                WHERE \(table) MATCH ? AND (s.project_id = ? OR s.session_id IS NULL)
                GROUP BY \(table).body, \(table).session_id, \(table).provider,
                    \(table).\(label), \(table).recorded_at
            )
            SELECT 1 FROM candidates c
            LEFT JOIN context_sessions s ON s.session_id = c.session_id
            WHERE s.session_id IS NULL OR s.provider IS NOT c.provider
                OR c.occurrences != (
                    SELECT COUNT(*) FROM context_entries e
                    WHERE e.session_id = c.session_id AND e.entry_kind = '\(kind)'
                        AND \(body) = c.body AND e.role_or_tool = c.label
                        AND e.recorded_at = c.recorded_at
                )
            LIMIT 1;
            """, [.text(expression), .text(projectID.rawValue)])
        guard corrupt.isEmpty else { throw SQLiteContextReadFailure.malformedEntry }
    }
}
