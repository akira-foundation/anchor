import Foundation

public struct WorkspaceChange: Sendable, Hashable {
    public let workspaceURL: URL
    public let changedPaths: Set<String>

    public init(workspaceURL: URL, changedPaths: Set<String>) {
        self.workspaceURL = workspaceURL
        self.changedPaths = changedPaths
    }
}

public protocol WorkspaceChangeObserving: Sendable {
    func observeWorkspaceChanges(at workspaceURL: URL) -> AsyncStream<WorkspaceChange>
    func stopObserving() async
}
