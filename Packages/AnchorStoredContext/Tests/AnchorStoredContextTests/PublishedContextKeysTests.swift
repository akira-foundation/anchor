import AnchorDomain
import Testing

@testable import AnchorStoredContext

@Suite("Published context keys")
struct PublishedContextKeysTests {
    private let projectID = ProjectID()
    private let source = KnowledgeEntrySource.session(SessionID())

    @Test("the same project and source always name the same knowledge key")
    func sameProjectAndSourceShareKey() throws {
        let firstKey = try PublishedContextKeys.knowledgeKey(for: projectID, source: source)
        let secondKey = try PublishedContextKeys.knowledgeKey(for: projectID, source: source)

        #expect(firstKey != nil)
        #expect(firstKey == secondKey)
    }

    @Test("another source names another knowledge key")
    func anotherSourceNamesAnotherKey() throws {
        let sessionKey = try PublishedContextKeys.knowledgeKey(for: projectID, source: source)
        let otherSessionKey = try PublishedContextKeys.knowledgeKey(
            for: projectID, source: .session(SessionID()))

        #expect(sessionKey != otherSessionKey)
    }

    @Test("another project names another knowledge key for the same source")
    func anotherProjectNamesAnotherKey() throws {
        let projectKey = try PublishedContextKeys.knowledgeKey(for: projectID, source: source)
        let otherProjectKey = try PublishedContextKeys.knowledgeKey(
            for: ProjectID(), source: source)

        #expect(projectKey != otherProjectKey)
    }
}
