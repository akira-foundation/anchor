import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@Suite("SQLite device presence snapshot store")
struct SQLiteDevicePresenceSnapshotStoreTests {
    @Test("recording the same device replaces only its older presence")
    func recordPresenceUpsertsByProjectAndDevice() async throws {
        let projectID = ProjectID.derived(fromSeed: "presence-project")
        let firstDeviceID = DeviceID.derived(fromSeed: "first-device")
        let secondDeviceID = DeviceID.derived(fromSeed: "second-device")
        let store = try await SQLiteDevicePresenceSnapshotStore(
            database: SQLiteDatabase(fileURL: nil))

        try await store.recordPresence(
            presence(projectID, firstDeviceID, secondsSinceEpoch: 10))
        try await store.recordPresence(
            presence(projectID, secondDeviceID, secondsSinceEpoch: 20))
        try await store.recordPresence(
            presence(projectID, firstDeviceID, secondsSinceEpoch: 30))

        let presences = try await store.presences(onProject: projectID)
        #expect(presences.map(\.deviceID) == [firstDeviceID, secondDeviceID])
        #expect(presences.map(\.lastSeenAt) == [date(30), date(20)])
    }

    @Test("successful replacement removes devices absent from the new project snapshot")
    func replacementIsAtomicAndProjectScoped() async throws {
        let projectID = ProjectID.derived(fromSeed: "replaced-project")
        let otherProjectID = ProjectID.derived(fromSeed: "preserved-project")
        let removedDeviceID = DeviceID.derived(fromSeed: "removed-device")
        let retainedDeviceID = DeviceID.derived(fromSeed: "retained-device")
        let foreignDeviceID = DeviceID.derived(fromSeed: "foreign-device")
        let store = try await SQLiteDevicePresenceSnapshotStore(
            database: SQLiteDatabase(fileURL: nil))

        try await store.recordPresence(presence(projectID, removedDeviceID, secondsSinceEpoch: 10))
        try await store.recordPresence(
            presence(otherProjectID, foreignDeviceID, secondsSinceEpoch: 11))
        try await store.replacePresences(
            [presence(projectID, retainedDeviceID, secondsSinceEpoch: 20)], forProject: projectID)

        #expect(
            try await store.presences(onProject: projectID).map(\.deviceID) == [retainedDeviceID])
        #expect(
            try await store.presences(onProject: otherProjectID).map(\.deviceID)
                == [foreignDeviceID])
    }

    @Test("an existing phase 25 database migrates idempotently")
    func migrationPreservesExistingTablesAndPresenceRows() async throws {
        let fileURL = makeFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let projectID = ProjectID.derived(fromSeed: "migration-project")
        let deviceID = DeviceID.derived(fromSeed: "migration-device")
        let database = try SQLiteDatabase(fileURL: fileURL)
        try await database.execute(
            "CREATE TABLE phase_25_record (identifier TEXT PRIMARY KEY);"
                + " INSERT INTO phase_25_record VALUES ('preserved');")
        let store = try await SQLiteDevicePresenceSnapshotStore(database: database)
        try await store.recordPresence(presence(projectID, deviceID, secondsSinceEpoch: 42.125))

        let reopenedDatabase = try SQLiteDatabase(fileURL: fileURL)
        let reopenedStore = try await SQLiteDevicePresenceSnapshotStore(database: reopenedDatabase)
        _ = try await SQLiteDevicePresenceSnapshotStore(database: reopenedDatabase)
        let preservedRows = try await reopenedDatabase.run(
            "SELECT identifier FROM phase_25_record;")

        #expect(preservedRows.first?["identifier"] == .text("preserved"))
        #expect(try await reopenedStore.presences(onProject: projectID).first?.deviceID == deviceID)
        #expect(
            try await reopenedStore.presences(onProject: projectID).first?.lastSeenAt
                == date(42.125))
    }

    @Test("equal timestamps are ordered by device identifier")
    func equalPresenceTimestampsHaveStableOrder() async throws {
        let projectID = ProjectID.derived(fromSeed: "ordered-project")
        let deviceIDs = [
            DeviceID.derived(fromSeed: "z-device"),
            DeviceID.derived(fromSeed: "a-device"),
            DeviceID.derived(fromSeed: "m-device"),
        ]
        let store = try await SQLiteDevicePresenceSnapshotStore(
            database: SQLiteDatabase(fileURL: nil))
        for deviceID in deviceIDs.reversed() {
            try await store.recordPresence(presence(projectID, deviceID, secondsSinceEpoch: 50))
        }

        let sortedDeviceIDs = deviceIDs.sorted { $0.rawValue < $1.rawValue }
        #expect(try await store.presences(onProject: projectID).map(\.deviceID) == sortedDeviceIDs)
    }

    private func presence(
        _ projectID: ProjectID, _ deviceID: DeviceID, secondsSinceEpoch: TimeInterval
    ) -> DevicePresence {
        DevicePresence(
            projectID: projectID, deviceID: deviceID,
            lastSeenAt: date(secondsSinceEpoch))
    }

    private func date(_ secondsSinceEpoch: TimeInterval) -> Date {
        Date(timeIntervalSince1970: secondsSinceEpoch)
    }

    private func makeFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-device-presence-\(UUID().uuidString)/context.sqlite")
    }
}
