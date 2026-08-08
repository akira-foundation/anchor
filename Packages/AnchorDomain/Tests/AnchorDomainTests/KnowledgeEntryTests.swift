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
            source: .session(sourceSessionID, messageIDs: sourceMessageIDs),
            createdAt: Date(timeIntervalSince1970: 0)
        )

        #expect(knowledgeEntry.source == .session(sourceSessionID, messageIDs: sourceMessageIDs))
    }
}
