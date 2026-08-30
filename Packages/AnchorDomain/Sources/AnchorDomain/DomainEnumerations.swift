public enum DevicePlatform: String, Sendable, Codable {
    case macOS
    case iOS
    case iPadOS
}

public enum AgentProvider: String, Sendable, Codable {
    case claude
    case codex
    case superpowers
    case graphify
}

public enum ConversationRole: String, Sendable, Codable {
    case user
    case assistant
    case system
    case tool
}

public enum KnowledgeEntryState: String, Sendable, Codable {
    case current
    case superseded
}

public enum KnowledgeEntryKind: String, Sendable, Codable {
    case summary
    case decision
    case todo
    case question
    case risk
    case architecture
}

public enum SyncOperationState: String, Sendable, Codable {
    case pending
    case uploading
    case synced
    case failed
    case conflicted
}

public enum DevicePresenceState: String, Sendable, Codable {
    case active
    case recentlyActive
    case stoppedOrUnknown
}
