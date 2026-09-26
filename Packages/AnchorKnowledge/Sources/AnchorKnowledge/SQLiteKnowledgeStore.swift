import AnchorDomain
import AnchorPersistence
import Foundation

public enum SQLiteKnowledgeStoreFailure: Error, Sendable, Equatable {
    case malformedEntryRecord
    case invalidSource(KnowledgeEntryID)
    case invalidSupportingMessageIdentifiers(KnowledgeEntryID)
}

public struct SQLiteKnowledgeStore: KnowledgeStore {
    private let database: SQLiteDatabase

    public init(existingDatabase: SQLiteDatabase) {
        database = existingDatabase
    }

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
                origin TEXT NOT NULL DEFAULT 'classified',
                supporting_message_ids TEXT NOT NULL DEFAULT '[]',
                state TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS knowledge_by_project
                ON knowledge_entries (project_id, state);
            CREATE INDEX IF NOT EXISTS knowledge_by_source ON knowledge_entries (source);
            """
        )
        try await addOriginColumnIfMissing()
        try await addSupportingMessageIDsColumnIfMissing()
        try await supersedeInferredEntriesWithoutEvidence()
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
        let rows = try await database.run(
            """
            SELECT id, project_id, kind, summary_text, source, source_content_hash,
                   origin, supporting_message_ids, state, created_at
            FROM knowledge_entries
            WHERE project_id = ? AND state \(Self.stateFilter(includingSuperseded))
            ORDER BY created_at, id;
            """,
            [.text(projectID.rawValue)]
        )

        return try rows.map(Self.entry)
    }

    public func loadCurrentEntries(
        forProject projectID: ProjectID, kind: KnowledgeEntryKind, limit: Int
    ) async throws -> (entries: [KnowledgeEntry], hasMore: Bool) {
        let rows = try await database.run(
            """
            SELECT id, project_id, kind, summary_text, source, source_content_hash,
                   origin, supporting_message_ids, state, created_at
            FROM knowledge_entries
            WHERE project_id = ? AND kind = ? AND state = ?
            ORDER BY created_at DESC, id ASC
            LIMIT ?;
            """,
            [
                .text(projectID.rawValue), .text(kind.rawValue),
                .text(KnowledgeEntryState.current.rawValue),
                .integer(Int64(max(0, limit)) + 1),
            ])
        let decodedEntries = try rows.map(Self.entry)
        return (
            entries: Array(decodedEntries.prefix(max(0, limit))),
            hasMore: decodedEntries.count > max(0, limit)
        )
    }

    public func loadLatestCurrentEntryDate(
        forProject projectID: ProjectID
    ) async throws -> Date? {
        let rows = try await database.run(
            """
            SELECT created_at FROM knowledge_entries
            WHERE project_id = ? AND state = ?
            ORDER BY created_at DESC, id ASC
            LIMIT 1;
            """,
            [.text(projectID.rawValue), .text(KnowledgeEntryState.current.rawValue)])
        guard let row = rows.first else { return nil }
        guard let createdAt = row["created_at"]?.integer
        else { throw SQLiteKnowledgeStoreFailure.malformedEntryRecord }
        return Date(timeIntervalSince1970: TimeInterval(createdAt))
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
                origin, supporting_message_ids, state, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                state = excluded.state,
                summary_text = excluded.summary_text,
                source_content_hash = excluded.source_content_hash,
                origin = excluded.origin,
                supporting_message_ids = excluded.supporting_message_ids;
            """,
            [
                .text(entry.id.rawValue),
                .text(entry.projectID.rawValue),
                .text(entry.kind.rawValue),
                .text(entry.summaryText),
                .text(try Self.encoded(entry.source)),
                .text(entry.sourceContentHash.rawValue),
                .text(entry.origin.rawValue),
                .text(try Self.encoded(entry.supportingMessageIDs)),
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

    private static func encoded(_ supportingMessageIDs: [MessageID]) throws -> String {
        String(decoding: try JSONEncoder().encode(supportingMessageIDs), as: UTF8.self)
    }

    private static func entry(from row: [String: SQLiteValue]) throws -> KnowledgeEntry {
        guard let identifier = row["id"]?.text.flatMap(KnowledgeEntryID.init(rawValue:)) else {
            throw SQLiteKnowledgeStoreFailure.malformedEntryRecord
        }
        guard let projectID = row["project_id"]?.text.flatMap(ProjectID.init(rawValue:)),
            let kind = row["kind"]?.text.flatMap(KnowledgeEntryKind.init(rawValue:)),
            let summaryText = row["summary_text"]?.text,
            let contentHash = row["source_content_hash"]?.text.flatMap(ContentHash.init(rawValue:)),
            let origin = row["origin"]?.text.flatMap(KnowledgeEntryOrigin.init(rawValue:)),
            let encodedSupportingMessageIDs = row["supporting_message_ids"]?.text,
            let state = row["state"]?.text.flatMap(KnowledgeEntryState.init(rawValue:)),
            let createdAt = row["created_at"]?.integer
        else { throw SQLiteKnowledgeStoreFailure.malformedEntryRecord }

        guard let encodedSource = row["source"]?.text,
            let source = Self.decodedSource(from: encodedSource)
        else { throw SQLiteKnowledgeStoreFailure.invalidSource(identifier) }

        let supportingMessageIDs: [MessageID]
        do {
            supportingMessageIDs = try JSONDecoder().decode(
                [MessageID].self, from: Data(encodedSupportingMessageIDs.utf8))
        } catch {
            throw SQLiteKnowledgeStoreFailure.invalidSupportingMessageIdentifiers(identifier)
        }

        return KnowledgeEntry(
            id: identifier,
            projectID: projectID,
            kind: kind,
            summaryText: summaryText,
            source: source,
            sourceContentHash: contentHash,
            origin: origin,
            supportingMessageIDs: supportingMessageIDs,
            state: state,
            createdAt: Date(timeIntervalSince1970: TimeInterval(createdAt))
        )
    }

    private static func decodedSource(from text: String) -> KnowledgeEntrySource? {
        try? JSONDecoder().decode(KnowledgeEntrySource.self, from: Data(text.utf8))
    }

    private func addOriginColumnIfMissing() async throws {
        let columns = try await database.run("PRAGMA table_info(knowledge_entries);")
        guard !columns.contains(where: { $0["name"]?.text == "origin" }) else { return }

        try await database.execute(
            "ALTER TABLE knowledge_entries ADD COLUMN origin TEXT NOT NULL DEFAULT 'classified';")
    }

    private func addSupportingMessageIDsColumnIfMissing() async throws {
        let columns = try await database.run("PRAGMA table_info(knowledge_entries);")
        guard !columns.contains(where: { $0["name"]?.text == "supporting_message_ids" }) else {
            return
        }

        try await database.execute(
            "ALTER TABLE knowledge_entries ADD COLUMN supporting_message_ids TEXT NOT NULL DEFAULT '[]';"
        )
    }

    private func supersedeInferredEntriesWithoutEvidence() async throws {
        try await database.run(
            """
            UPDATE knowledge_entries
            SET state = ?
            WHERE origin = ?
              AND supporting_message_ids = '[]'
              AND state = ?;
            """,
            [
                .text(KnowledgeEntryState.superseded.rawValue),
                .text(KnowledgeEntryOrigin.inferred.rawValue),
                .text(KnowledgeEntryState.current.rawValue),
            ])
    }
}
