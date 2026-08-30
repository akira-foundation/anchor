import AnchorDomain
import Foundation

public struct SQLiteWorkspaceStore: WorkspaceStore {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) async throws {
        self.database = database
        try await database.execute(
            """
            CREATE TABLE IF NOT EXISTS workspaces (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                device_id TEXT NOT NULL,
                local_repository_path TEXT
            );
            CREATE INDEX IF NOT EXISTS workspaces_by_project ON workspaces (project_id);
            """
        )
    }

    public func storeWorkspace(_ workspace: Workspace) async throws {
        try await database.run(
            """
            INSERT INTO workspaces (id, project_id, device_id, local_repository_path)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                project_id = excluded.project_id,
                device_id = excluded.device_id,
                local_repository_path = excluded.local_repository_path;
            """,
            [
                .text(workspace.id.rawValue),
                .text(workspace.projectID.rawValue),
                .text(workspace.deviceID.rawValue),
                workspace.localRepositoryURL.map { .text($0.path(percentEncoded: false)) } ?? .null,
            ]
        )
    }

    public func loadWorkspace(withIdentifier identifier: WorkspaceID) async throws -> Workspace? {
        try await database.run(
            """
            SELECT id, project_id, device_id, local_repository_path
            FROM workspaces WHERE id = ?;
            """,
            [.text(identifier.rawValue)]
        )
        .compactMap(Self.workspace(from:))
        .first
    }

    public func loadWorkspaces(forProject projectIdentifier: ProjectID) async throws -> [Workspace]
    {
        try await database.run(
            """
            SELECT id, project_id, device_id, local_repository_path
            FROM workspaces WHERE project_id = ? ORDER BY id;
            """,
            [.text(projectIdentifier.rawValue)]
        )
        .compactMap(Self.workspace(from:))
    }

    private static func workspace(from row: [String: SQLiteValue]) -> Workspace? {
        guard let identifier = row["id"]?.text.flatMap(WorkspaceID.init(rawValue:)),
            let projectID = row["project_id"]?.text.flatMap(ProjectID.init(rawValue:)),
            let deviceID = row["device_id"]?.text.flatMap(DeviceID.init(rawValue:))
        else { return nil }

        return Workspace(
            id: identifier,
            projectID: projectID,
            deviceID: deviceID,
            localRepositoryURL: row["local_repository_path"]?.text.map { URL(filePath: $0) }
        )
    }
}
