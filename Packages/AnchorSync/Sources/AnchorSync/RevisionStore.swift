import AnchorApplication

public struct RevisionStore: Sendable {
    public let journal: any ArtifactRevisionJournal
    public let contents: any ArtifactContentStore

    public init(journal: any ArtifactRevisionJournal, contents: any ArtifactContentStore) {
        self.journal = journal
        self.contents = contents
    }
}
