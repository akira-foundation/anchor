import AnchorApplication
import AnchorDomain
import AnchorPlatformMacOS
import AnchorStorage
import Foundation
import Testing

@Suite("Stored sync ports")
struct StoredSyncPortsTests {
    @Test("a cursor survives a new store over the same storage")
    func aCursorSurvivesANewStoreOverTheSameStorage() async throws {
        let storage = InMemoryStorageProvider()

        try await StoredSyncCursorStore(storage: storage).recordCursor("page-2")

        #expect(try await StoredSyncCursorStore(storage: storage).cursor() == "page-2")
    }

    @Test("no cursor was recorded before the first run")
    func noCursorWasRecordedBeforeTheFirstRun() async throws {
        #expect(try await StoredSyncCursorStore(storage: InMemoryStorageProvider()).cursor() == nil)
    }

    @Test("a recorded divergence comes back with the pair that produced it")
    func aRecordedDivergenceComesBackWithThePairThatProducedIt() async throws {
        let storage = InMemoryStorageProvider()
        let divergence = ArtifactDivergence(
            artifactID: ArtifactID(),
            localRevisionID: RevisionID(),
            remoteRevisionID: RevisionID(),
            resolution: .awaitingDecision,
            detectedAt: Date(timeIntervalSince1970: 0)
        )

        try await StoredArtifactDivergenceJournal(storage: storage).recordDivergence(divergence)

        #expect(
            try await StoredArtifactDivergenceJournal(storage: storage).divergences()
                == [divergence])
    }

    @Test("the feed reports the revisions the other side published")
    func theFeedReportsTheRevisionsTheOtherSidePublished() async throws {
        let storage = InMemoryStorageProvider()
        let journal = StoredArtifactRevisionJournal(
            storage: storage, contentStore: StoredArtifactContentStore(storage: storage))
        let revision = try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: ArtifactID(), parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data("anchor".utf8)),
                deviceID: DeviceID(), createdAt: Date(timeIntervalSince1970: 0)
            )
        )
        try await journal.recordRevision(revision)

        let page = try await StoredRevisionFeed(storage: storage).revisions(after: nil)

        #expect(page.revisions == [revision])
    }
}
