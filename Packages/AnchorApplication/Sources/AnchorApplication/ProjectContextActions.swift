import AnchorDomain
import Foundation

public protocol AuthorizedProjectContextReading: Sendable {
    func loadAuthorizedProjectContext() async throws -> ProjectContext
}

public struct ProjectContextRequest: Sendable {
    public init() {}
}

public struct ResolveCurrentProjectAction: Action {
    private let availability: any ContextAvailabilityReading
    private let workspace: any AuthorizedProjectContextReading

    public init(
        workspace: any AuthorizedProjectContextReading, availability: any ContextAvailabilityReading
    ) {
        self.availability = availability
        self.workspace = workspace
    }

    public func perform(_ request: ProjectContextRequest) async throws -> ProjectContext {
        try await queryContext(availability: availability) { _ in
            try await workspace.loadAuthorizedProjectContext()
        }
    }
}

public struct BuildProjectResumeAction: Action {
    private let availability: any ContextAvailabilityReading
    private let workspace: any AuthorizedProjectContextReading
    private let resumes: any ProjectResumeReading

    public init(
        workspace: any AuthorizedProjectContextReading, resumes: any ProjectResumeReading,
        availability: any ContextAvailabilityReading
    ) {
        self.availability = availability
        self.workspace = workspace
        self.resumes = resumes
    }

    public func perform(_ request: ProjectContextRequest) async throws -> ProjectResume {
        try await queryContext(availability: availability) { _ in
            let project = try await workspace.loadAuthorizedProjectContext()
            return try await resumes.loadProjectResume(for: project, limits: .compact)
        }
    }
}
