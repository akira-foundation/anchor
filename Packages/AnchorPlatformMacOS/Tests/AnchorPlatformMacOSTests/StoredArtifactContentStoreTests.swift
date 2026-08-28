import AnchorApplicationTestSupport
import AnchorDomain
import AnchorPlatformMacOS
import AnchorStorage
import Foundation
import Testing

@Suite("Stored artifact content store")
struct StoredArtifactContentStoreTests {
    @Test("it honours the artifact content store contract")
    func itHonoursTheArtifactContentStoreContract() async throws {
        try await verifyArtifactContentStoreContract {
            StoredArtifactContentStore(storage: InMemoryStorageProvider())
        }
    }

    @Test("what it keeps survives a new store over the same storage")
    func whatItKeepsSurvivesANewStoreOverTheSameStorage() async throws {
        let storage = InMemoryStorageProvider()
        let revisionID = RevisionID()

        try await StoredArtifactContentStore(storage: storage)
            .storeContent(Data("remembered".utf8), forRevision: revisionID)

        let reopened = StoredArtifactContentStore(storage: storage)

        #expect(try await reopened.content(forRevision: revisionID) == Data("remembered".utf8))
    }
}
