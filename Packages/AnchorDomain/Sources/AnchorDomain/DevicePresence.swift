import Foundation

public struct DevicePresence: Sendable, Hashable, Codable, Identifiable {
    public let id: PresenceID
    public let projectID: ProjectID
    public let deviceID: DeviceID
    public let provider: AgentProvider
    public let sessionID: SessionID?
    public let lastSeenAt: Date
    public let state: DevicePresenceState

    public init(
        id: PresenceID,
        projectID: ProjectID,
        deviceID: DeviceID,
        provider: AgentProvider,
        sessionID: SessionID?,
        lastSeenAt: Date,
        state: DevicePresenceState
    ) {
        self.id = id
        self.projectID = projectID
        self.deviceID = deviceID
        self.provider = provider
        self.sessionID = sessionID
        self.lastSeenAt = lastSeenAt
        self.state = state
    }
}
