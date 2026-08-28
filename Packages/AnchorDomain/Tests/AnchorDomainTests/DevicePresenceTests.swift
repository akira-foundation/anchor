import Foundation
import Testing

@testable import AnchorDomain

@Suite("Device presence")
struct DevicePresenceTests {
    private let readingInstant = Date(timeIntervalSince1970: 10_000)

    private func presence(seenSecondsAgo elapsed: TimeInterval) -> DevicePresence {
        DevicePresence(
            projectID: ProjectID(),
            deviceID: DeviceID(),
            lastSeenAt: readingInstant.addingTimeInterval(-elapsed)
        )
    }

    @Test(
        "a device seen within the active window is active",
        arguments: [0, 1, DevicePresence.activeWindow]
    )
    func aDeviceSeenWithinTheActiveWindowIsActive(_ elapsed: TimeInterval) {
        #expect(presence(seenSecondsAgo: elapsed).state(asOf: readingInstant) == .active)
    }

    @Test(
        "a device seen past the active window but inside the next one is recently active",
        arguments: [DevicePresence.activeWindow + 1, DevicePresence.recentlyActiveWindow]
    )
    func aDeviceSeenPastTheActiveWindowIsRecentlyActive(_ elapsed: TimeInterval) {
        #expect(presence(seenSecondsAgo: elapsed).state(asOf: readingInstant) == .recentlyActive)
    }

    @Test("a device not seen for longer than both windows is stopped or unknown")
    func aDeviceNotSeenForLongerThanBothWindowsIsStoppedOrUnknown() {
        let stale = presence(seenSecondsAgo: DevicePresence.recentlyActiveWindow + 1)

        #expect(stale.state(asOf: readingInstant) == .stoppedOrUnknown)
    }

    @Test("a device whose clock ran ahead is not treated as stale")
    func aDeviceWhoseClockRanAheadIsNotTreatedAsStale() {
        #expect(presence(seenSecondsAgo: -600).state(asOf: readingInstant) == .active)
    }
}
