import Foundation

public enum ConversationEntry: Sendable, Hashable, Codable {
    case message(ConversationMessage)
    case toolActivity(ToolActivity)

    public var timestamp: Date {
        switch self {
        case .message(let message): message.timestamp
        case .toolActivity(let activity): activity.timestamp
        }
    }

    public var orderingIdentifier: String {
        switch self {
        case .message(let message): message.id.rawValue
        case .toolActivity(let activity): activity.id.rawValue
        }
    }
}
