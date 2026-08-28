import Foundation

public struct DevicePresence: Sendable, Hashable, Codable {
    public static let activeWindow: TimeInterval = 120
    public static let recentlyActiveWindow: TimeInterval = 1800

    public let projectID: ProjectID
    public let deviceID: DeviceID
    public let lastSeenAt: Date

    public init(projectID: ProjectID, deviceID: DeviceID, lastSeenAt: Date) {
        self.projectID = projectID
        self.deviceID = deviceID
        self.lastSeenAt = lastSeenAt
    }

    public func state(asOf instant: Date) -> DevicePresenceState {
        let elapsed = instant.timeIntervalSince(lastSeenAt)

        guard elapsed > Self.activeWindow else { return .active }
        guard elapsed > Self.recentlyActiveWindow else { return .recentlyActive }

        return .stoppedOrUnknown
    }
}
