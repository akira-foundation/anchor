import AnchorDomain
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Which machine this is, across restarts")
struct DeviceIdentityStoreTests {
    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-device-\(UUID().uuidString)/device.json")
    }

    @Test("a machine that has never run before is given an identity")
    func machineThatHasNeverRunBeforeIsGivenAnIdentity() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let device = try DeviceIdentityStore(fileURL: fileURL).deviceCreatingIfNeeded(
            displayName: "Studio")

        #expect(device.displayName == "Studio")
        #expect(device.platform == .macOS)
        #expect(device.canDiscoverLocalProviders)
    }

    @Test("the same machine is the same machine on the next run")
    func sameMachineIsSameMachineOnNextRun() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = DeviceIdentityStore(fileURL: fileURL)
        let first = try store.deviceCreatingIfNeeded(displayName: "Studio")
        let second = try DeviceIdentityStore(fileURL: fileURL).deviceCreatingIfNeeded(
            displayName: "Studio")

        #expect(first.id == second.id)
    }

    @Test("two machines are not the same machine")
    func twoMachinesAreNotSameMachine() throws {
        let one = temporaryFileURL()
        let another = temporaryFileURL()
        defer {
            try? FileManager.default.removeItem(at: one.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: another.deletingLastPathComponent())
        }

        let first = try DeviceIdentityStore(fileURL: one).deviceCreatingIfNeeded(
            displayName: "Studio")
        let second = try DeviceIdentityStore(fileURL: another).deviceCreatingIfNeeded(
            displayName: "Laptop")

        #expect(first.id != second.id)
    }

    @Test("renaming the machine does not make it a different machine")
    func renamingMachineDoesNotMakeItDifferentMachine() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let before = try DeviceIdentityStore(fileURL: fileURL).deviceCreatingIfNeeded(
            displayName: "Studio")
        let after = try DeviceIdentityStore(fileURL: fileURL).deviceCreatingIfNeeded(
            displayName: "Studio Renamed")

        #expect(before.id == after.id)
        #expect(after.displayName == "Studio Renamed")
    }

    @Test("an identity that cannot be read is not silently replaced")
    func identityThatCannotBeReadIsNotSilentlyReplaced() throws {
        let fileURL = temporaryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        #expect(throws: DeviceIdentityStore.Failure.self) {
            try DeviceIdentityStore(fileURL: fileURL).deviceCreatingIfNeeded(
                displayName: "Studio")
        }
    }
}
