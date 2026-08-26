public struct Project: Sendable, Hashable, Codable, Identifiable {
    public let id: ProjectID
    public let displayName: String
    public let canonicalRepositoryRemote: CanonicalRepositoryRemote

    public init(
        id: ProjectID,
        displayName: String,
        canonicalRepositoryRemote: CanonicalRepositoryRemote
    ) {
        self.id = id
        self.displayName = displayName
        self.canonicalRepositoryRemote = canonicalRepositoryRemote
    }
}
