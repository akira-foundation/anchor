import Foundation

public struct Workspace: Sendable, Hashable, Codable, Identifiable {
    public let id: WorkspaceID
    public let projectID: ProjectID
    public let deviceID: DeviceID
    public let localRepositoryURL: URL?

    public init(id: WorkspaceID, projectID: ProjectID, deviceID: DeviceID, localRepositoryURL: URL?) {
        self.id = id
        self.projectID = projectID
        self.deviceID = deviceID
        self.localRepositoryURL = localRepositoryURL
    }
}
