import AnchorApplication
import AnchorDomain
import AnchorPersistence

extension SQLiteKnowledgeStore {
    public func listCurrentKnowledge(
        forProject projectID: ProjectID,
        kind: KnowledgeEntryKind?, origin: KnowledgeEntryOrigin?,
        page: ContextPageRequest, binding: ContextCursorBinding
    ) async throws -> ContextPage<KnowledgeEntry> {
        let position = try KnowledgeContextCursor.decode(
            page.cursor, projectID: projectID, kind: kind, origin: origin, binding: binding)
        var statement = """
            SELECT id, project_id, kind, summary_text, source, source_content_hash,
                   origin, supporting_message_ids, state, created_at
            FROM knowledge_entries
            WHERE project_id = ? AND state = ?
            """
        var parameters: [SQLiteValue] = [
            .text(projectID.rawValue), .text(KnowledgeEntryState.current.rawValue),
        ]
        if let kind {
            statement += " AND kind = ?"
            parameters.append(.text(kind.rawValue))
        }
        if let origin {
            statement += " AND origin = ?"
            parameters.append(.text(origin.rawValue))
        }
        if let position {
            statement += " AND (created_at < ? OR (created_at = ? AND id > ?))"
            parameters += [
                .integer(position.createdAt), .integer(position.createdAt),
                .text(position.knowledgeEntryID),
            ]
        }
        statement += " ORDER BY created_at DESC, id ASC LIMIT ?;"
        parameters.append(.integer(Int64(page.limit) + 1))

        let rows = try await database.run(statement, parameters)
        let decodedEntries = try rows.map(Self.entry)
        let records = Array(decodedEntries.prefix(page.limit))
        let nextCursor =
            try rows.count > page.limit
            ? KnowledgeContextCursor.encode(
                after: records.last, projectID: projectID, kind: kind,
                origin: origin, binding: binding)
            : nil
        return ContextPage(records: records, nextCursor: nextCursor)
    }

    public func loadCurrentKnowledge(
        withIdentifier knowledgeEntryID: KnowledgeEntryID,
        forProject projectID: ProjectID
    ) async throws -> KnowledgeEntry? {
        try await database.run(
            """
            SELECT id, project_id, kind, summary_text, source, source_content_hash,
                   origin, supporting_message_ids, state, created_at
            FROM knowledge_entries
            WHERE id = ? AND project_id = ? AND state = ? LIMIT 1;
            """,
            [
                .text(knowledgeEntryID.rawValue), .text(projectID.rawValue),
                .text(KnowledgeEntryState.current.rawValue),
            ]
        )
        .first
        .map(Self.entry)
    }
}
