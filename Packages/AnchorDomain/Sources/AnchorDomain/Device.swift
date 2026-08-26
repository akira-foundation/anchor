public struct Device: Sendable, Hashable, Codable, Identifiable {
    public let id: DeviceID
    public let displayName: String
    public let platform: DevicePlatform
    public let capabilities: Set<DeviceCapability>

    public init(id: DeviceID, displayName: String, platform: DevicePlatform) {
        self.id = id
        self.displayName = displayName
        self.platform = platform
        self.capabilities = DeviceCapability.supported(on: platform)
    }

    public init?(
        id: DeviceID,
        displayName: String,
        platform: DevicePlatform,
        capabilities: Set<DeviceCapability>
    ) {
        guard capabilities.isSubset(of: DeviceCapability.supported(on: platform)) else {
            return nil
        }

        self.id = id
        self.displayName = displayName
        self.platform = platform
        self.capabilities = capabilities
    }

    public var canDiscoverLocalProviders: Bool {
        capabilities.contains(.developmentWorkspace)
    }
}

extension Device {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedDevice = Device(
            id: try container.decode(DeviceID.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            platform: try container.decode(DevicePlatform.self, forKey: .platform),
            capabilities: try container.decode(Set<DeviceCapability>.self, forKey: .capabilities)
        )

        guard let decodedDevice else {
            throw DecodingError.dataCorruptedError(
                forKey: .capabilities,
                in: container,
                debugDescription: "Device claims a capability its platform does not support"
            )
        }

        self = decodedDevice
    }
}
