import AnchorApplication
import AnchorDomain
import Foundation

enum DevicePresenceSnapshotFailure: Error, Sendable, Equatable {
    case malformedPresenceRecord
}

public struct SQLiteDevicePresenceSnapshotStore: DevicePresenceSnapshotStore {
    private let database: SQLiteDatabase

    public init(existingDatabase: SQLiteDatabase) {
        database = existingDatabase
    }

    public init(database: SQLiteDatabase) async throws {
        self.database = database
        try await database.execute(
            """
            CREATE TABLE IF NOT EXISTS context_device_presences (
                project_id TEXT NOT NULL,
                device_id TEXT NOT NULL,
                last_seen_at INTEGER NOT NULL,
                PRIMARY KEY (project_id, device_id)
            );
            CREATE INDEX IF NOT EXISTS context_device_presences_by_project_activity
                ON context_device_presences(project_id, last_seen_at DESC, device_id ASC);
            """)
    }

    public func recordPresence(_ presence: DevicePresence) async throws {
        try await database.run(
            """
            INSERT INTO context_device_presences (project_id, device_id, last_seen_at)
            VALUES (?, ?, ?)
            ON CONFLICT(project_id, device_id) DO UPDATE SET
                last_seen_at = excluded.last_seen_at
            WHERE excluded.last_seen_at >= context_device_presences.last_seen_at;
            """,
            Self.parameters(for: presence))
    }

    public func replacePresences(
        _ presences: [DevicePresence], forProject projectID: ProjectID
    ) async throws {
        try await database.withinTransaction { isolatedDatabase in
            try isolatedDatabase.run(
                "DELETE FROM context_device_presences WHERE project_id = ?;",
                [.text(projectID.rawValue)])
            for presence in presences where presence.projectID == projectID {
                try isolatedDatabase.run(
                    """
                    INSERT INTO context_device_presences (project_id, device_id, last_seen_at)
                    VALUES (?, ?, ?);
                    """,
                    Self.parameters(for: presence))
            }
        }
    }

    public func presences(onProject projectID: ProjectID) async throws -> [DevicePresence] {
        try await database.run(
            """
            SELECT project_id, device_id, last_seen_at
            FROM context_device_presences
            WHERE project_id = ?
            ORDER BY last_seen_at DESC, device_id ASC;
            """,
            [.text(projectID.rawValue)]
        ).map(Self.presence)
    }

    private static func parameters(for presence: DevicePresence) -> [SQLiteValue] {
        [
            .text(presence.projectID.rawValue),
            .text(presence.deviceID.rawValue),
            .integer(microseconds(for: presence.lastSeenAt)),
        ]
    }

    private static func presence(
        from row: [String: SQLiteValue]
    ) throws -> DevicePresence {
        guard let projectID = row["project_id"]?.text.flatMap(ProjectID.init(rawValue:)),
            let deviceID = row["device_id"]?.text.flatMap(DeviceID.init(rawValue:)),
            let lastSeenAt = row["last_seen_at"]?.integer
        else { throw DevicePresenceSnapshotFailure.malformedPresenceRecord }

        return DevicePresence(
            projectID: projectID,
            deviceID: deviceID,
            lastSeenAt: Date(timeIntervalSince1970: TimeInterval(lastSeenAt) / 1_000_000))
    }

    private static func microseconds(for date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    }
}
