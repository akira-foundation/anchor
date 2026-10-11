import AnchorDomain
import AnchorPersistence

extension SQLiteKnowledgeStore {
    private static let knowledgeSourcesStatement = """
        SELECT source, MIN(created_at) AS first_created_at FROM knowledge_entries
        WHERE project_id = ?
        GROUP BY source
        ORDER BY first_created_at, source;
        """

    public func loadPublishableKnowledge(
        forProject projectID: ProjectID
    ) async throws -> (currentEntries: [KnowledgeEntry], sources: [KnowledgeEntrySource]) {
        let projectParameters: [SQLiteValue] = [.text(projectID.rawValue)]
        let (entryRows, sourceRows) = try await database.withinTransaction { database in
            (
                try database.run(
                    Self.entriesStatement(includingSuperseded: false), projectParameters),
                try database.run(Self.knowledgeSourcesStatement, projectParameters)
            )
        }

        return (try entryRows.map(Self.entry), try Self.knowledgeSources(from: sourceRows))
    }

    private static func knowledgeSources(
        from rows: [[String: SQLiteValue]]
    ) throws -> [KnowledgeEntrySource] {
        try rows.map { row in
            guard let source = row["source"]?.text.flatMap(Self.decodedSource(from:))
            else { throw SQLiteKnowledgeStoreFailure.malformedEntryRecord }
            return source
        }
    }
}
