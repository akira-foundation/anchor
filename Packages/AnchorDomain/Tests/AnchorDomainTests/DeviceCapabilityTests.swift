import Foundation
import Testing

@testable import AnchorDomain

@Suite("Device capabilities")
struct DeviceCapabilityTests {
    @Test("a Mac derives every capability from its platform")
    func aMacDerivesEveryCapabilityFromItsPlatform() {
        let mac = Device(id: DeviceID(), displayName: "Studio", platform: .macOS)

        #expect(mac.capabilities == Set(DeviceCapability.allCases))
    }

    @Test(
        "a handheld device derives only the capabilities it can honour",
        arguments: [DevicePlatform.iOS, DevicePlatform.iPadOS]
    )
    func aHandheldDeviceDerivesOnlyTheCapabilitiesItCanHonour(_ platform: DevicePlatform) {
        let device = Device(id: DeviceID(), displayName: "Companion", platform: platform)

        #expect(device.capabilities == [.contextMonitoring, .conflictReview])
        #expect(!device.capabilities.contains(.developmentWorkspace))
        #expect(!device.capabilities.contains(.localMCP))
        #expect(!device.capabilities.contains(.localProviderDiscovery))
    }

    @Test("a device may restrict what its platform allows")
    func aDeviceMayRestrictWhatItsPlatformAllows() throws {
        let macWithoutXcode = try #require(
            Device(
                id: DeviceID(),
                displayName: "Build Server",
                platform: .macOS,
                capabilities: [.contextMonitoring, .conflictReview]
            )
        )

        #expect(!macWithoutXcode.capabilities.contains(.developmentWorkspace))
    }

    @Test("a device without capabilities is valid and discovers nothing")
    func aDeviceWithoutCapabilitiesIsValidAndDiscoversNothing() throws {
        let dormantDevice = try #require(
            Device(id: DeviceID(), displayName: "Dormant", platform: .macOS, capabilities: [])
        )

        #expect(dormantDevice.capabilities.isEmpty)
        #expect(!dormantDevice.canDiscoverLocalProviders)
    }

    @Test("a device cannot claim a capability its platform does not support")
    func aDeviceCannotClaimACapabilityItsPlatformDoesNotSupport() {
        let overreachingPhone = Device(
            id: DeviceID(),
            displayName: "iPhone",
            platform: .iOS,
            capabilities: [.contextMonitoring, .localMCP]
        )

        #expect(overreachingPhone == nil)
    }

    @Test("only a device with a development workspace discovers local providers")
    func onlyADeviceWithADevelopmentWorkspaceDiscoversLocalProviders() throws {
        let mac = Device(id: DeviceID(), displayName: "Studio", platform: .macOS)
        let phone = Device(id: DeviceID(), displayName: "iPhone", platform: .iOS)
        let restrictedMac = try #require(
            Device(
                id: DeviceID(), displayName: "Build Server", platform: .macOS,
                capabilities: [.localMCP])
        )

        #expect(mac.canDiscoverLocalProviders)
        #expect(!phone.canDiscoverLocalProviders)
        #expect(!restrictedMac.canDiscoverLocalProviders)
    }

    @Test("a device claiming a capability its platform forbids is rejected on decoding")
    func aDeviceClaimingACapabilityItsPlatformForbidsIsRejectedOnDecoding() {
        let encoded = Data(
            """
            {"id":"\(DeviceID().rawValue)","displayName":"iPhone","platform":"iOS",\
            "capabilities":["contextMonitoring","localMCP"]}
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Device.self, from: encoded)
        }
    }

    @Test("a device survives an encode and decode round trip with its capabilities")
    func aDeviceSurvivesAnEncodeAndDecodeRoundTripWithItsCapabilities() throws {
        let device = try #require(
            Device(
                id: DeviceID(), displayName: "Studio", platform: .macOS,
                capabilities: [.contextMonitoring])
        )
        let decoded = try JSONDecoder().decode(Device.self, from: JSONEncoder().encode(device))

        #expect(decoded == device)
    }
}
