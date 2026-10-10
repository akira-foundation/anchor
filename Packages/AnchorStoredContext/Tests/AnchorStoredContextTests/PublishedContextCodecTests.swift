import AnchorApplication
import AnchorDomain
import Foundation
import Testing

@testable import AnchorStoredContext

@Suite("Published context codec")
struct PublishedContextCodecTests {
    @Test("a project descriptor decodes to what was encoded")
    func projectDescriptorRoundTrips() throws {
        let descriptor = PublishedProjectDescriptor(
            projectID: ProjectID(), displayName: "Anchor",
            canonicalRepositoryRemote: CanonicalRepositoryRemote(
                rawValue: "github.com/akira-foundation/anchor"))

        let decoded = try PublishedContextCodec.decode(
            PublishedProjectDescriptor.self, from: try PublishedContextCodec.encode(descriptor))

        #expect(decoded == descriptor)
    }

    @Test("a knowledge snapshot decodes to what was encoded")
    func knowledgeSnapshotRoundTrips() throws {
        let projectID = ProjectID()
        let source = KnowledgeEntrySource.session(SessionID())
        let entry = KnowledgeEntry(
            id: KnowledgeEntryID(), projectID: projectID, kind: .architecture,
            summaryText: "Contracts live in AnchorApplication", source: source,
            sourceContentHash: .digest(of: Data("s".utf8)), origin: .inferred,
            supportingMessageIDs: [MessageID()], createdAt: Date(timeIntervalSince1970: 1_234.5))
        let snapshot = try #require(
            KnowledgeSourceSnapshot(projectID: projectID, source: source, entries: [entry]))

        let decoded = try PublishedContextCodec.decode(
            KnowledgeSourceSnapshot.self, from: try PublishedContextCodec.encode(snapshot))

        #expect(decoded == snapshot)
    }

    @Test("an unknown format version is refused")
    func unknownFormatVersionIsRefused() {
        let futureBody = Data(#"{"formatVersion":2,"body":{}}"#.utf8)

        #expect(throws: PublishedContextDecodingFailure.unsupportedFormatVersion(2)) {
            try PublishedContextCodec.decode(PublishedProjectDescriptor.self, from: futureBody)
        }
    }

    @Test("the knowledge key does not expose the source identifier")
    func knowledgeKeyHidesTheSource() throws {
        let sessionID = SessionID()
        let key = try #require(
            try PublishedContextKeys.knowledgeKey(for: ProjectID(), source: .session(sessionID)))

        #expect(!key.rawValue.contains(sessionID.rawValue))
        #expect(key.rawValue.hasPrefix("knowledge/"))
    }
}
