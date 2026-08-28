import Foundation
import Testing

@testable import AnchorDomain

@Suite("Domain identifiers")
struct DomainIdentifierTests {
    @Test("every domain identifier restores from a well formed raw value")
    func everyDomainIdentifierRestoresFromAWellFormedRawValue() throws {
        let rawValue = UUID().uuidString

        #expect(try #require(ProjectID(rawValue: rawValue)).rawValue == rawValue)
        #expect(try #require(DeviceID(rawValue: rawValue)).rawValue == rawValue)
        #expect(try #require(WorkspaceID(rawValue: rawValue)).rawValue == rawValue)
        #expect(try #require(SessionID(rawValue: rawValue)).rawValue == rawValue)
        #expect(try #require(ArtifactID(rawValue: rawValue)).rawValue == rawValue)
        #expect(try #require(RevisionID(rawValue: rawValue)).rawValue == rawValue)
        #expect(try #require(MessageID(rawValue: rawValue)).rawValue == rawValue)
        #expect(try #require(KnowledgeEntryID(rawValue: rawValue)).rawValue == rawValue)
        #expect(try #require(SyncOperationID(rawValue: rawValue)).rawValue == rawValue)
    }

    @Test("every domain identifier rejects a raw value that is not a UUID")
    func everyDomainIdentifierRejectsARawValueThatIsNotAUniversallyUniqueIdentifier() {
        #expect(ProjectID(rawValue: "not-a-uuid") == nil)
        #expect(DeviceID(rawValue: "not-a-uuid") == nil)
        #expect(WorkspaceID(rawValue: "not-a-uuid") == nil)
        #expect(SessionID(rawValue: "not-a-uuid") == nil)
        #expect(ArtifactID(rawValue: "not-a-uuid") == nil)
        #expect(RevisionID(rawValue: "not-a-uuid") == nil)
        #expect(MessageID(rawValue: "not-a-uuid") == nil)
        #expect(KnowledgeEntryID(rawValue: "not-a-uuid") == nil)
        #expect(SyncOperationID(rawValue: "not-a-uuid") == nil)
    }
}
