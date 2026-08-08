import Foundation

public struct ConversationMessage: Sendable, Hashable, Codable, Identifiable {
    public let id: MessageID
    public let sessionID: SessionID
    public let role: ConversationRole
    public let content: String
    public let timestamp: Date

    public init(id: MessageID, sessionID: SessionID, role: ConversationRole, content: String, timestamp: Date) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
