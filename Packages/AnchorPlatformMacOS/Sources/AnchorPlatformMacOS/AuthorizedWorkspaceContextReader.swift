import AnchorApplication
import Foundation

public struct AuthorizedWorkspaceContextReader: AuthorizedProjectContextReading {
    private let workspacePath: String
    private let configuration: ObservedWorkspaceConfiguration
    private let projects: any ProjectContextReading

    public init(
        requestedWorkspacePath: String, configurationURL: URL, projects: any ProjectContextReading
    ) throws {
        guard requestedWorkspacePath.hasPrefix("/") else {
            throw ContextQueryFailure.workspaceNotAuthorized
        }
        workspacePath = WorkspacePath.comparable(URL(filePath: requestedWorkspacePath))
        configuration = ObservedWorkspaceConfiguration(fileURL: configurationURL)
        self.projects = projects
        if let observed = try configuration.observedWorkspace() {
            guard workspacePath == WorkspacePath.comparable(observed.workspaceURL) else {
                throw ContextQueryFailure.workspaceNotAuthorized
            }
        }
    }

    public func loadAuthorizedProjectContext() async throws -> ProjectContext {
        guard let observed = try configuration.observedWorkspace() else {
            throw ContextQueryFailure.workspaceNotConfigured
        }
        guard workspacePath == WorkspacePath.comparable(observed.workspaceURL) else {
            throw ContextQueryFailure.workspaceNotAuthorized
        }
        guard
            let project = try await projects.loadProjectContext(
                forWorkspaceAt: observed.workspaceURL),
            project.projectID == observed.projectID
        else { throw ContextQueryFailure.contextUnavailable }
        return project
    }
}
