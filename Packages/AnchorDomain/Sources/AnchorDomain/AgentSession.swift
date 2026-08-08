import Foundation

public struct AgentSession: Sendable, Hashable, Codable, Identifiable {
    public let id: SessionID
    public let projectID: ProjectID
    public let provider: AgentProvider
    public let startedAt: Date
    public let updatedAt: Date

    public init(
        id: SessionID, projectID: ProjectID, provider: AgentProvider, startedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.provider = provider
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}
