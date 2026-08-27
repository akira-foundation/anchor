public enum ArtifactRetention: String, Sendable, Codable, CaseIterable {
    case fullHistory
    case latestRevisionOnly
}
