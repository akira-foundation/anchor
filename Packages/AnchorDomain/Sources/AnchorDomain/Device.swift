public struct Device: Sendable, Hashable, Codable, Identifiable {
    public let id: DeviceID
    public let displayName: String
    public let platform: DevicePlatform

    public init(id: DeviceID, displayName: String, platform: DevicePlatform) {
        self.id = id
        self.displayName = displayName
        self.platform = platform
    }
}
