import AnchorDomain
import Foundation

public struct DeviceIdentityStore: Sendable {
    public enum Failure: Error, Sendable, Equatable {
        case unreadable(URL)
        case unwritable(URL)
    }

    private struct StoredIdentity: Codable {
        let deviceID: String
    }

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func deviceCreatingIfNeeded(displayName: String) throws(Failure) -> Device {
        Device(id: try identifierCreatingIfNeeded(), displayName: displayName, platform: .macOS)
    }

    private func identifierCreatingIfNeeded() throws(Failure) -> DeviceID {
        if let existing = try existingIdentifier() { return existing }

        let created = DeviceID()

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder()
                .encode(StoredIdentity(deviceID: created.rawValue))
                .write(to: fileURL)
        } catch {
            throw .unwritable(fileURL)
        }

        return created
    }

    private func existingIdentifier() throws(Failure) -> DeviceID? {
        guard let contents = try? Data(contentsOf: fileURL) else { return nil }

        guard
            let stored = try? JSONDecoder().decode(StoredIdentity.self, from: contents),
            let identifier = DeviceID(rawValue: stored.deviceID)
        else { throw .unreadable(fileURL) }

        return identifier
    }
}
