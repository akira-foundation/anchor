import AnchorDomain
import AnchorFoundation
import Foundation

public struct ObservedWorkspace: Sendable, Hashable {
    public let workspaceURL: URL
    public let projectName: String

    public init(workspaceURL: URL, projectName: String) {
        self.workspaceURL = URL(filePath: WorkspacePath.comparable(workspaceURL))
        self.projectName = projectName
    }

    public var projectID: ProjectID { .derived(fromSeed: projectName) }
}

public struct ObservedWorkspaceConfiguration: Sendable {
    public enum Failure: Error, Sendable, Equatable {
        case unreadable(URL)
        case projectUnnamed(URL)
        case workspaceUnnamed(URL)
        case workspaceAbsent(String)
    }

    private struct StoredConfiguration: Decodable {
        let workspacePath: String?
        let projectName: String?
    }

    public static func defaultFileURL(inSupportDirectoryAt supportDirectoryURL: URL) -> URL {
        supportDirectoryURL.appending(path: "observed-workspace.json")
    }

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func observedWorkspace() throws(Failure) -> ObservedWorkspace? {
        guard let contents = try? Data(contentsOf: fileURL) else { return nil }

        guard
            let stored = try? JSONDecoder().decode(StoredConfiguration.self, from: contents)
        else { throw .unreadable(fileURL) }

        let projectName = stored.projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let projectName, !projectName.isEmpty else { throw .projectUnnamed(fileURL) }

        let workspacePath = stored.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let workspacePath, !workspacePath.isEmpty else { throw .workspaceUnnamed(fileURL) }

        let observed = ObservedWorkspace(
            workspaceURL: URL(filePath: workspacePath), projectName: projectName)

        var pointsAtDirectory = ObjCBool(false)
        guard
            FileManager.default.fileExists(
                atPath: observed.workspaceURL.path(percentEncoded: false),
                isDirectory: &pointsAtDirectory),
            pointsAtDirectory.boolValue
        else { throw .workspaceAbsent(workspacePath) }

        return observed
    }
}
