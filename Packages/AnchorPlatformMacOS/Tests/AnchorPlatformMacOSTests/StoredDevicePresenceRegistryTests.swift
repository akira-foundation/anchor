import AnchorDomain
import AnchorPlatformMacOS
import AnchorStorage
import Foundation
import Testing

@Suite("Stored device presence registry")
struct StoredDevicePresenceRegistryTests {
    private let projectID = ProjectID()

    private func presence(
        of deviceID: DeviceID, secondsSinceEpoch: TimeInterval
    )
        -> DevicePresence
    {
        DevicePresence(
            projectID: projectID,
            deviceID: deviceID,
            lastSeenAt: Date(timeIntervalSince1970: secondsSinceEpoch)
        )
    }

    @Test("announcing again replaces what the same device said before")
    func announcingAgainReplacesWhatTheSameDeviceSaidBefore() async throws {
        let registry = StoredDevicePresenceRegistry(storage: InMemoryStorageProvider())
        let deviceID = DeviceID()

        try await registry.announcePresence(presence(of: deviceID, secondsSinceEpoch: 0))
        try await registry.announcePresence(presence(of: deviceID, secondsSinceEpoch: 60))

        let announced = try await registry.presences(onProject: projectID)

        #expect(announced.count == 1)
        #expect(announced.first?.lastSeenAt == Date(timeIntervalSince1970: 60))
    }

    @Test("two devices on one project are both reported")
    func twoDevicesOnOneProjectAreBothReported() async throws {
        let registry = StoredDevicePresenceRegistry(storage: InMemoryStorageProvider())
        let studio = DeviceID()
        let laptop = DeviceID()

        try await registry.announcePresence(presence(of: studio, secondsSinceEpoch: 0))
        try await registry.announcePresence(presence(of: laptop, secondsSinceEpoch: 0))

        let announced = try await registry.presences(onProject: projectID)

        #expect(Set(announced.map(\.deviceID)) == [studio, laptop])
    }

    @Test("a project nobody announced reports nobody")
    func aProjectNobodyAnnouncedReportsNobody() async throws {
        let registry = StoredDevicePresenceRegistry(storage: InMemoryStorageProvider())

        try await registry.announcePresence(presence(of: DeviceID(), secondsSinceEpoch: 0))

        #expect(try await registry.presences(onProject: ProjectID()).isEmpty)
    }

    @Test("what one machine announced survives a new registry over the same storage")
    func whatOneMachineAnnouncedSurvivesANewRegistryOverTheSameStorage() async throws {
        let storage = InMemoryStorageProvider()
        let deviceID = DeviceID()

        try await StoredDevicePresenceRegistry(storage: storage)
            .announcePresence(presence(of: deviceID, secondsSinceEpoch: 42))

        let reopened = try await StoredDevicePresenceRegistry(storage: storage)
            .presences(onProject: projectID)

        #expect(reopened.first?.deviceID == deviceID)
    }
}
