import AnchorApplication
import AnchorDomain
import AnchorStorage
import Foundation

public struct StoredDevicePresenceRegistry: DevicePresenceRegistry {
    private static let presencePrefix = "presence"

    private let storage: any StorageProvider

    public init(storage: any StorageProvider) {
        self.storage = storage
    }

    public func announcePresence(_ presence: DevicePresence) async throws {
        guard let key = storageKey(for: presence) else { return }

        try await storage.putObject(
            StorageObject(key: key, contents: try JSONEncoder().encode(presence)),
            precondition: .none
        )
    }

    public func presences(onProject projectID: ProjectID) async throws -> [DevicePresence] {
        guard let prefix = projectPrefix(for: projectID) else { return [] }

        var found: [DevicePresence] = []
        for metadata in try await storage.listObjects(withPrefix: prefix) {
            guard let stored = try await storage.object(for: metadata.key),
                let presence = try? JSONDecoder().decode(
                    DevicePresence.self, from: stored.object.contents)
            else { continue }

            found.append(presence)
        }

        return found
    }

    private func projectPrefix(for projectID: ProjectID) -> StorageKey? {
        StorageKey(rawValue: "\(Self.presencePrefix)/\(projectID.rawValue)")
    }

    private func storageKey(for presence: DevicePresence) -> StorageKey? {
        StorageKey(
            rawValue:
                "\(Self.presencePrefix)/\(presence.projectID.rawValue)"
                + "/\(presence.deviceID.rawValue)"
        )
    }
}
