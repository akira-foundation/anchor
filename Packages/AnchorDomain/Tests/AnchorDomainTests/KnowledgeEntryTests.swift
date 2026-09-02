import Foundation
import Testing

@testable import AnchorDomain

@Suite("KnowledgeEntry source")
struct KnowledgeEntryTests {
    @Test("an entry extracted from an artifact reports that artifact as its source")
    func entryExtractedFromAnArtifactReportsThatArtifactAsItsSource() {
        let sourceArtifactID = ArtifactID()
        let knowledgeEntry = KnowledgeEntry(
            id: KnowledgeEntryID(),
            projectID: ProjectID(),
            kind: .decision,
            summaryText: "SQLite chosen for the local index",
            source: .artifact(sourceArtifactID),
            sourceContentHash: ContentHash.digest(of: Data("source".utf8)),
            createdAt: Date(timeIntervalSince1970: 0)
        )

        #expect(knowledgeEntry.source == .artifact(sourceArtifactID))
    }

    @Test("an entry extracted from a session reports that session and its messages")
    func entryExtractedFromASessionReportsThatSessionAndItsMessages() {
        let sourceSessionID = SessionID()
        let sourceMessageIDs = [MessageID()]
        let knowledgeEntry = KnowledgeEntry(
            id: KnowledgeEntryID(),
            projectID: ProjectID(),
            kind: .question,
            summaryText: "Which algorithm backs ContentHash?",
            source: .session(sourceSessionID),
            sourceContentHash: ContentHash.digest(of: Data("source".utf8)),
            createdAt: Date(timeIntervalSince1970: 0)
        )

        #expect(knowledgeEntry.source == .session(sourceSessionID))
    }

    @Test("an entry is current until its source moves on")
    func anEntryIsCurrentUntilItsSourceMovesOn() {
        let entry = KnowledgeEntry(
            id: KnowledgeEntryID(),
            projectID: ProjectID(),
            kind: .decision,
            summaryText: "SQLite chosen for the local index",
            source: .artifact(ArtifactID()),
            sourceContentHash: ContentHash.digest(of: Data("source".utf8)),
            createdAt: Date(timeIntervalSince1970: 0)
        )

        #expect(entry.state == .current)
    }
}
