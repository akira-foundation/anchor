import AnchorDomain
import AnchorPersistence
import Foundation

public struct SQLiteKnowledgeStore: KnowledgeStore {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) async throws {
        self.database = database
        try await database.execute(
            """
            CREATE TABLE IF NOT EXISTS knowledge_entries (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                summary_text TEXT NOT NULL,
                source TEXT NOT NULL,
                source_content_hash TEXT NOT NULL,
                state TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS knowledge_by_project
                ON knowledge_entries (project_id, state);
            CREATE INDEX IF NOT EXISTS knowledge_by_source ON knowledge_entries (source);
            """
        )
    }

    public func recordEntries(
        _ entries: [KnowledgeEntry], supersedingEntriesFrom source: KnowledgeEntrySource
    ) async throws {
        try await database.run(
            """
            UPDATE knowledge_entries SET state = ? WHERE source = ? AND state = ?;
            """,
            [
                .text(KnowledgeEntryState.superseded.rawValue),
                .text(try Self.encoded(source)),
                .text(KnowledgeEntryState.current.rawValue),
            ]
        )

        for entry in entries {
            try await record(entry)
        }
    }

    public func entries(
        forProject projectID: ProjectID, includingSuperseded: Bool
    ) async throws -> [KnowledgeEntry] {
        try await database.run(
            """
            SELECT id, project_id, kind, summary_text, source, source_content_hash,
                   state, created_at
            FROM knowledge_entries
            WHERE project_id = ? AND state \(Self.stateFilter(includingSuperseded))
            ORDER BY created_at, id;
            """,
            [.text(projectID.rawValue)]
        )
        .compactMap(Self.entry(from:))
    }

    private static func stateFilter(_ includingSuperseded: Bool) -> String {
        guard includingSuperseded else { return "= '\(KnowledgeEntryState.current.rawValue)'" }

        return "IS NOT NULL"
    }

    private func record(_ entry: KnowledgeEntry) async throws {
        try await database.run(
            """
            INSERT INTO knowledge_entries (
                id, project_id, kind, summary_text, source, source_content_hash,
                state, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                state = excluded.state,
                summary_text = excluded.summary_text,
                source_content_hash = excluded.source_content_hash;
            """,
            [
                .text(entry.id.rawValue),
                .text(entry.projectID.rawValue),
                .text(entry.kind.rawValue),
                .text(entry.summaryText),
                .text(try Self.encoded(entry.source)),
                .text(entry.sourceContentHash.rawValue),
                .text(entry.state.rawValue),
                .integer(Int64(entry.createdAt.timeIntervalSince1970)),
            ]
        )
    }

    private static func encoded(_ source: KnowledgeEntrySource) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        return String(decoding: try encoder.encode(source), as: UTF8.self)
    }

    private static func entry(from row: [String: SQLiteValue]) -> KnowledgeEntry? {
        guard let identifier = row["id"]?.text.flatMap(KnowledgeEntryID.init(rawValue:)),
            let projectID = row["project_id"]?.text.flatMap(ProjectID.init(rawValue:)),
            let kind = row["kind"]?.text.flatMap(KnowledgeEntryKind.init(rawValue:)),
            let summaryText = row["summary_text"]?.text,
            let source = row["source"]?.text.flatMap(Self.decodedSource(from:)),
            let contentHash = row["source_content_hash"]?.text.flatMap(ContentHash.init(rawValue:)),
            let state = row["state"]?.text.flatMap(KnowledgeEntryState.init(rawValue:)),
            let createdAt = row["created_at"]?.integer
        else { return nil }

        return KnowledgeEntry(
            id: identifier,
            projectID: projectID,
            kind: kind,
            summaryText: summaryText,
            source: source,
            sourceContentHash: contentHash,
            state: state,
            createdAt: Date(timeIntervalSince1970: TimeInterval(createdAt))
        )
    }

    private static func decodedSource(from text: String) -> KnowledgeEntrySource? {
        try? JSONDecoder().decode(KnowledgeEntrySource.self, from: Data(text.utf8))
    }
}
