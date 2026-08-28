import AnchorDomain

public struct RemoteRevisionPage: Sendable, Hashable {
    public let revisions: [ArtifactRevision]
    public let cursor: String?

    public init(revisions: [ArtifactRevision], cursor: String?) {
        self.revisions = revisions
        self.cursor = cursor
    }
}

public protocol RemoteRevisionFeed: Sendable {
    func revisions(after cursor: String?) async throws -> RemoteRevisionPage
}

public protocol SyncCursorStore: Sendable {
    func cursor() async throws -> String?
    func recordCursor(_ cursor: String) async throws
}

public protocol ArtifactDivergenceJournal: Sendable {
    func recordDivergence(_ divergence: ArtifactDivergence) async throws
    func divergences() async throws -> [ArtifactDivergence]
}
