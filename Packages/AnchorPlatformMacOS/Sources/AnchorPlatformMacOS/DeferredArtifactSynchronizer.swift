import AnchorApplication
import AnchorDomain
import Foundation

public struct DeferredArtifactSynchronizer: ArtifactRevisionSynchronizing, Sendable {
    public init() {}

    public func synchronizePendingArtifactRevisions() async throws {}
}

public struct DeferredDevicePresenceRegistry: DevicePresenceRegistry, Sendable {
    public init() {}

    public func announcePresence(_ presence: DevicePresence) async throws {}

    public func presences(onProject projectID: ProjectID) async throws -> [DevicePresence] { [] }
}
