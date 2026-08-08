public enum KnowledgeEntrySource: Sendable, Hashable, Codable {
    case artifact(ArtifactID)
    case session(SessionID, messageIDs: [MessageID])
}
