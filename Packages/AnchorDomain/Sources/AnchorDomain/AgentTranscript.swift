import Foundation

public struct AgentTranscript: Sendable, Hashable, Codable {
    public let session: AgentSession
    public let messages: [ConversationMessage]

    public init(session: AgentSession, messages: [ConversationMessage]) {
        self.session = session
        self.messages = messages
    }

    public var inConversationOrder: AgentTranscript {
        AgentTranscript(
            session: session,
            messages: messages.sorted {
                ($0.timestamp, $0.id.rawValue) < ($1.timestamp, $1.id.rawValue)
            }
        )
    }
}
