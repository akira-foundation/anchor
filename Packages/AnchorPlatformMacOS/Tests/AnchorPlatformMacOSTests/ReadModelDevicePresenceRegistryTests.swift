import AnchorApplication
import AnchorDomain
import AnchorPersistence
import AnchorPlatformMacOS
import Foundation
import Testing

@Suite("Read-model device presence registry")
struct ReadModelDevicePresenceRegistryTests {
    @Test("local presence is durable even when remote publication fails")
    func announcementWritesSnapshotBeforeRemote() async throws {
        let projectID = ProjectID.derived(fromSeed: "announcement-project")
        let announced = presence(projectID, "announced", secondsSinceEpoch: 10)
        let snapshot = try await makeSnapshot()
        let registry = ReadModelDevicePresenceRegistry(
            snapshot: snapshot, remote: PresenceRegistryStub(announcementFailure: true))

        await #expect(throws: PresenceRegistryStub.Failure.unavailable) {
            try await registry.announcePresence(announced)
        }

        #expect(try await snapshot.presences(onProject: projectID) == [announced])
    }

    @Test("successful remote reads replace the cached project snapshot")
    func remotePresenceRefreshReplacesSnapshot() async throws {
        let projectID = ProjectID.derived(fromSeed: "refresh-project")
        let stale = presence(projectID, "stale", secondsSinceEpoch: 10)
        let refreshed = presence(projectID, "refreshed", secondsSinceEpoch: 20)
        let snapshot = try await makeSnapshot()
        try await snapshot.recordPresence(stale)
        let registry = ReadModelDevicePresenceRegistry(
            snapshot: snapshot, remote: PresenceRegistryStub(returnedPresences: [refreshed]))

        #expect(try await registry.presences(onProject: projectID) == [refreshed])
        #expect(try await snapshot.presences(onProject: projectID) == [refreshed])
    }

    @Test("remote failure returns the last persisted snapshot")
    func remoteFailurePreservesOfflineContext() async throws {
        let projectID = ProjectID.derived(fromSeed: "offline-project")
        let cached = presence(projectID, "cached", secondsSinceEpoch: 30)
        let snapshot = try await makeSnapshot()
        try await snapshot.recordPresence(cached)
        let registry = ReadModelDevicePresenceRegistry(
            snapshot: snapshot, remote: PresenceRegistryStub(readFailure: true))

        #expect(try await registry.presences(onProject: projectID) == [cached])
        #expect(try await snapshot.presences(onProject: projectID) == [cached])
    }

    @Test("remote presences from another project are excluded")
    func remoteRefreshCannotCrossProjects() async throws {
        let projectID = ProjectID.derived(fromSeed: "authorized-project")
        let otherProjectID = ProjectID.derived(fromSeed: "foreign-project")
        let authorized = presence(projectID, "authorized", secondsSinceEpoch: 40)
        let foreign = presence(otherProjectID, "foreign", secondsSinceEpoch: 50)
        let snapshot = try await makeSnapshot()
        let registry = ReadModelDevicePresenceRegistry(
            snapshot: snapshot,
            remote: PresenceRegistryStub(returnedPresences: [foreign, authorized]))

        #expect(try await registry.presences(onProject: projectID) == [authorized])
        #expect(try await snapshot.presences(onProject: otherProjectID).isEmpty)
    }

    private func makeSnapshot() async throws -> SQLiteDevicePresenceSnapshotStore {
        try await SQLiteDevicePresenceSnapshotStore(database: SQLiteDatabase(fileURL: nil))
    }

    private func presence(
        _ projectID: ProjectID, _ deviceSeed: String, secondsSinceEpoch: TimeInterval
    ) -> DevicePresence {
        DevicePresence(
            projectID: projectID, deviceID: DeviceID.derived(fromSeed: deviceSeed),
            lastSeenAt: Date(timeIntervalSince1970: secondsSinceEpoch))
    }
}

private struct PresenceRegistryStub: DevicePresenceRegistry {
    enum Failure: Error { case unavailable }

    let returnedPresences: [DevicePresence]
    let announcementFailure: Bool
    let readFailure: Bool

    init(
        returnedPresences: [DevicePresence] = [], announcementFailure: Bool = false,
        readFailure: Bool = false
    ) {
        self.returnedPresences = returnedPresences
        self.announcementFailure = announcementFailure
        self.readFailure = readFailure
    }

    func announcePresence(_ presence: DevicePresence) async throws {
        if announcementFailure { throw Failure.unavailable }
    }

    func presences(onProject projectID: ProjectID) async throws -> [DevicePresence] {
        if readFailure { throw Failure.unavailable }
        return returnedPresences
    }
}
