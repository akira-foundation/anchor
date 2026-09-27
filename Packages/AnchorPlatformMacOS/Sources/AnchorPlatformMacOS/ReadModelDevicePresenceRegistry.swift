import AnchorApplication
import AnchorDomain

public struct ReadModelDevicePresenceRegistry: DevicePresenceRegistry {
    private let snapshot: any DevicePresenceSnapshotStore
    private let remote: (any DevicePresenceRegistry)?

    public init(
        snapshot: any DevicePresenceSnapshotStore,
        remote: (any DevicePresenceRegistry)?
    ) {
        self.snapshot = snapshot
        self.remote = remote
    }

    public func announcePresence(_ presence: DevicePresence) async throws {
        try await snapshot.recordPresence(presence)
        try await remote?.announcePresence(presence)
    }

    public func presences(onProject projectID: ProjectID) async throws -> [DevicePresence] {
        guard let remote else { return try await snapshot.presences(onProject: projectID) }

        let remotePresences: [DevicePresence]
        do {
            remotePresences = try await remote.presences(onProject: projectID)
        } catch {
            return try await snapshot.presences(onProject: projectID)
        }

        let projectPresences = remotePresences.filter { $0.projectID == projectID }
        try await snapshot.replacePresences(projectPresences, forProject: projectID)
        return try await snapshot.presences(onProject: projectID)
    }
}
