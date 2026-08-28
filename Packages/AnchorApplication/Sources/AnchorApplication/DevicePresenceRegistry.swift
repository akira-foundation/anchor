import AnchorDomain

public protocol DevicePresenceRegistry: Sendable {
    func announcePresence(_ presence: DevicePresence) async throws
    func presences(onProject projectID: ProjectID) async throws -> [DevicePresence]
}
