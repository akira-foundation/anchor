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

    @Test("an entry records whether a model inferred it")
    func entryRecordsWhetherModelInferredIt() {
        let entry = KnowledgeEntry(
            id: KnowledgeEntryID(),
            projectID: ProjectID(),
            kind: .decision,
            summaryText: "keep the journal local",
            source: .session(SessionID()),
            sourceContentHash: ContentHash.digest(of: Data("source".utf8)),
            origin: .inferred,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        #expect(entry.origin == .inferred)
    }

    @Test("an entry encoded before origins existed remains classified")
    func entryEncodedBeforeOriginsExistedRemainsClassified() throws {
        let entry = KnowledgeEntry(
            id: KnowledgeEntryID(),
            projectID: ProjectID(),
            kind: .decision,
            summaryText: "keep the journal local",
            source: .session(SessionID()),
            sourceContentHash: ContentHash.digest(of: Data("source".utf8)),
            origin: .inferred,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        var encoded = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        encoded.removeValue(forKey: "origin")

        let decoded = try JSONDecoder().decode(
            KnowledgeEntry.self, from: JSONSerialization.data(withJSONObject: encoded))

        #expect(decoded.origin == .classified)
    }
}
