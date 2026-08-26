public enum DeviceCapability: String, Sendable, Codable, CaseIterable {
    case developmentWorkspace
    case contextMonitoring
    case localMCP
    case localProviderDiscovery
    case conflictReview

    public static func supported(on platform: DevicePlatform) -> Set<DeviceCapability> {
        switch platform {
        case .macOS:
            Set(allCases)
        case .iOS, .iPadOS:
            [.contextMonitoring, .conflictReview]
        }
    }
}
