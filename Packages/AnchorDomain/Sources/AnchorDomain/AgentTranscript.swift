import Foundation

public struct AgentTranscript: Sendable, Hashable, Codable {
    public let session: AgentSession
    public let entries: [ConversationEntry]

    public init(session: AgentSession, entries: [ConversationEntry]) {
        self.session = session
        self.entries = entries
    }

    public var messages: [ConversationMessage] {
        entries.compactMap { entry in
            guard case .message(let message) = entry else { return nil }

            return message
        }
    }

    public var toolActivities: [ToolActivity] {
        entries.compactMap { entry in
            guard case .toolActivity(let activity) = entry else { return nil }

            return activity
        }
    }

    public var inConversationOrder: AgentTranscript {
        AgentTranscript(
            session: session,
            entries: entries.sorted {
                ($0.timestamp, $0.orderingIdentifier) < ($1.timestamp, $1.orderingIdentifier)
            }
        )
    }
}
