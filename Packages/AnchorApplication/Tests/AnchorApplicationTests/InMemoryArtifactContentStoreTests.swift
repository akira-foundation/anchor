import AnchorApplication
import AnchorApplicationTestSupport
import AnchorDomain
import Foundation
import Testing

actor InMemoryArtifactContentStore: ArtifactContentStore {
    private var contents: [RevisionID: Data] = [:]

    func storeContent(_ content: Data, forRevision revisionID: RevisionID) async throws {
        contents[revisionID] = content
    }

    func content(forRevision revisionID: RevisionID) async throws -> Data? {
        contents[revisionID]
    }

    func dropContent(forRevision revisionID: RevisionID) async throws {
        contents.removeValue(forKey: revisionID)
    }
}

@Suite("In memory artifact content store")
struct InMemoryArtifactContentStoreTests {
    @Test("it honours the artifact content store contract")
    func itHonoursTheArtifactContentStoreContract() async throws {
        try await verifyArtifactContentStoreContract { InMemoryArtifactContentStore() }
    }
}
