import AnchorDomain
import Foundation

public struct SQLiteProjectStore: ProjectStore {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) async throws {
        self.database = database
        try await database.execute(
            """
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                canonical_repository_remote TEXT NOT NULL
            );
            """
        )
    }

    public func storeProject(_ project: Project) async throws {
        try await database.run(
            """
            INSERT INTO projects (id, display_name, canonical_repository_remote)
            VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                display_name = excluded.display_name,
                canonical_repository_remote = excluded.canonical_repository_remote;
            """,
            [
                .text(project.id.rawValue),
                .text(project.displayName),
                .text(project.canonicalRepositoryRemote.rawValue),
            ]
        )
    }

    public func loadProject(withIdentifier identifier: ProjectID) async throws -> Project? {
        try await database.run(
            "SELECT id, display_name, canonical_repository_remote FROM projects WHERE id = ?;",
            [.text(identifier.rawValue)]
        )
        .compactMap(Self.project(from:))
        .first
    }

    public func loadAllProjects() async throws -> [Project] {
        try await database.run(
            """
            SELECT id, display_name, canonical_repository_remote
            FROM projects ORDER BY display_name;
            """
        )
        .compactMap(Self.project(from:))
    }

    private static func project(from row: [String: SQLiteValue]) -> Project? {
        guard let identifier = row["id"]?.text.flatMap(ProjectID.init(rawValue:)),
            let displayName = row["display_name"]?.text,
            let remote = row["canonical_repository_remote"]?.text
                .flatMap(CanonicalRepositoryRemote.init(rawValue:))
        else { return nil }

        return Project(
            id: identifier, displayName: displayName, canonicalRepositoryRemote: remote)
    }
}
