import AnchorDomain

public protocol DevicePresenceSnapshotStore: Sendable {
    func recordPresence(_ presence: DevicePresence) async throws
    func replacePresences(
        _ presences: [DevicePresence], forProject projectID: ProjectID
    ) async throws
    func presences(onProject projectID: ProjectID) async throws -> [DevicePresence]
}
