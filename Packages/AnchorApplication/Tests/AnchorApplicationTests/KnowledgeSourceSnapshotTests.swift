import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

@Suite("Knowledge source snapshot")
struct KnowledgeSourceSnapshotTests {
    private let projectID = ProjectID()
    private let source = KnowledgeEntrySource.session(SessionID())

    @Test("a superseded entry makes the snapshot invalid")
    func supersededEntryIsRejected() {
        let superseded = makeEntry(projectID: projectID, state: .superseded)

        #expect(
            KnowledgeSourceSnapshot(projectID: projectID, source: source, entries: [superseded])
                == nil)
    }

    @Test("an entry from another project makes the snapshot invalid")
    func foreignProjectEntryIsRejected() {
        let foreign = makeEntry(projectID: ProjectID(), state: .current)

        #expect(
            KnowledgeSourceSnapshot(projectID: projectID, source: source, entries: [foreign])
                == nil)
    }

    @Test("decoding a snapshot that carries a superseded entry fails")
    func decodingSupersededEntryFails() throws {
        let encodedSnapshot = try JSONEncoder().encode(
            UncheckedSnapshotBody(
                projectID: projectID, source: source,
                entries: [makeEntry(projectID: projectID, state: .superseded)]))

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KnowledgeSourceSnapshot.self, from: encodedSnapshot)
        }
    }

    @Test("decoding a snapshot of current entries succeeds")
    func decodingCurrentEntriesSucceeds() throws {
        let current = makeEntry(projectID: projectID, state: .current)
        let encodedSnapshot = try JSONEncoder().encode(
            UncheckedSnapshotBody(projectID: projectID, source: source, entries: [current]))

        let decoded = try JSONDecoder().decode(KnowledgeSourceSnapshot.self, from: encodedSnapshot)

        #expect(decoded.entries == [current])
    }

    private func makeEntry(projectID: ProjectID, state: KnowledgeEntryState) -> KnowledgeEntry {
        KnowledgeEntry(
            id: KnowledgeEntryID(), projectID: projectID, kind: .decision,
            summaryText: "Cut releases from develop", source: source,
            sourceContentHash: .digest(of: Data("develop".utf8)), state: state,
            createdAt: Date(timeIntervalSince1970: 1_000))
    }
}

private struct UncheckedSnapshotBody: Encodable {
    let projectID: ProjectID
    let source: KnowledgeEntrySource
    let entries: [KnowledgeEntry]
}
