import Foundation

public struct ToolActivity: Sendable, Hashable, Codable, Identifiable {
    public let id: ToolActivityID
    public let sessionID: SessionID
    public let toolName: String
    public let invocation: String
    public let outcome: String?
    public let failed: Bool
    public let timestamp: Date

    public init(
        id: ToolActivityID,
        sessionID: SessionID,
        toolName: String,
        invocation: String,
        outcome: String?,
        failed: Bool,
        timestamp: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.toolName = toolName
        self.invocation = invocation
        self.outcome = outcome
        self.failed = failed
        self.timestamp = timestamp
    }
}
