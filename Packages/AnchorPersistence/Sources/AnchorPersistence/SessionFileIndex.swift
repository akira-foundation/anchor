import Foundation

public struct RecordedSessionFile: Sendable, Hashable {
    public let path: String
    public let byteSize: Int64
    public let modifiedAt: Date
    public let artifactName: String
    public let contentHash: String

    public init(
        path: String, byteSize: Int64, modifiedAt: Date, artifactName: String, contentHash: String
    ) {
        self.path = path
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
        self.artifactName = artifactName
        self.contentHash = contentHash
    }

    public func describesFile(byteSize otherByteSize: Int64, modifiedAt otherInstant: Date) -> Bool
    {
        byteSize == otherByteSize
            && Int64(modifiedAt.timeIntervalSince1970) == Int64(otherInstant.timeIntervalSince1970)
    }
}

public struct SessionFileIndex: Sendable {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) async throws {
        self.database = database
        try await database.execute(
            """
            CREATE TABLE IF NOT EXISTS session_files (
                path TEXT PRIMARY KEY,
                byte_size INTEGER NOT NULL,
                modified_at INTEGER NOT NULL,
                artifact_name TEXT NOT NULL,
                content_hash TEXT NOT NULL
            );
            """
        )
    }

    public func recordedFile(atPath path: String) async throws -> RecordedSessionFile? {
        try await database.run(
            """
            SELECT path, byte_size, modified_at, artifact_name, content_hash
            FROM session_files WHERE path = ?;
            """,
            [.text(path)]
        )
        .compactMap(Self.recordedFile(from:))
        .first
    }

    public func record(_ file: RecordedSessionFile) async throws {
        try await database.run(
            """
            INSERT INTO session_files (path, byte_size, modified_at, artifact_name, content_hash)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                byte_size = excluded.byte_size,
                modified_at = excluded.modified_at,
                artifact_name = excluded.artifact_name,
                content_hash = excluded.content_hash;
            """,
            [
                .text(file.path),
                .integer(file.byteSize),
                .integer(Int64(file.modifiedAt.timeIntervalSince1970)),
                .text(file.artifactName),
                .text(file.contentHash),
            ]
        )
    }

    public func forgetFile(atPath path: String) async throws {
        try await database.run("DELETE FROM session_files WHERE path = ?;", [.text(path)])
    }

    private static func recordedFile(from row: [String: SQLiteValue]) -> RecordedSessionFile? {
        guard let path = row["path"]?.text,
            let byteSize = row["byte_size"]?.integer,
            let modifiedAt = row["modified_at"]?.integer,
            let artifactName = row["artifact_name"]?.text,
            let contentHash = row["content_hash"]?.text
        else { return nil }

        return RecordedSessionFile(
            path: path,
            byteSize: byteSize,
            modifiedAt: Date(timeIntervalSince1970: TimeInterval(modifiedAt)),
            artifactName: artifactName,
            contentHash: contentHash
        )
    }
}
