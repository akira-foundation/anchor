public protocol ProjectResumeReading: Sendable {
    func loadProjectResume(
        for project: ProjectContext, limits: ProjectResumeLimits
    ) async throws -> ProjectResume
}
