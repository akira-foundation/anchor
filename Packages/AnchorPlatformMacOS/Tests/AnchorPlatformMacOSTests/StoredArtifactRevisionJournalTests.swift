import AnchorApplication
import AnchorDomain
import AnchorStorage
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Stored artifact revision journal")
struct StoredArtifactRevisionJournalTests {
    private let artifactID = ArtifactID()
    private let deviceID = DeviceID()

    private func makeRevision(
        parent: RevisionID? = nil,
        contents: String
    ) throws -> ArtifactRevision {
        try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: artifactID, parentRevisionID: parent,
                contentHash: ContentHash.digest(of: Data(contents.utf8)),
                deviceID: deviceID, createdAt: Date(timeIntervalSince1970: 0)
            )
        )
    }

    @Test("a recorded revision is the latest one and survives a new journal")
    func aRecordedRevisionIsTheLatestOneAndSurvivesANewJournal() async throws {
        let storage = InMemoryStorageProvider()
        let revision = try makeRevision(contents: "one")

        try await StoredArtifactRevisionJournal(
            storage: storage, contentStore: StoredArtifactContentStore(storage: storage)
        ).recordRevision(revision)

        let reopened = StoredArtifactRevisionJournal(
            storage: storage, contentStore: StoredArtifactContentStore(storage: storage))
        #expect(try await reopened.latestRevision(forArtifact: artifactID)?.id == revision.id)
    }

    @Test("an artifact with no revisions has no latest one")
    func anArtifactWithNoRevisionsHasNoLatestOne() async throws {
        let storage = InMemoryStorageProvider()
        let journal = StoredArtifactRevisionJournal(
            storage: storage, contentStore: StoredArtifactContentStore(storage: storage))

        #expect(try await journal.latestRevision(forArtifact: ArtifactID()) == nil)
    }

    @Test("full history keeps every revision that was recorded")
    func fullHistoryKeepsEveryRevisionThatWasRecorded() async throws {
        let storage = InMemoryStorageProvider()
        let journal = StoredArtifactRevisionJournal(
            storage: storage, contentStore: StoredArtifactContentStore(storage: storage))
        let first = try makeRevision(contents: "one")
        let second = try makeRevision(parent: first.id, contents: "two")

        try await journal.recordRevision(first)
        try await journal.recordRevision(second)

        #expect(try await journal.revisionCount(forArtifact: artifactID) == 2)
        #expect(try await journal.latestRevision(forArtifact: artifactID)?.id == second.id)
    }

    @Test("a revision without ancestry drops the ones it superseded")
    func aRevisionWithoutAncestryDropsTheOnesItSuperseded() async throws {
        let storage = InMemoryStorageProvider()
        let journal = StoredArtifactRevisionJournal(
            storage: storage, contentStore: StoredArtifactContentStore(storage: storage))
        let first = try makeRevision(contents: "one")
        let second = try makeRevision(contents: "two")

        try await journal.recordRevision(first)
        try await journal.recordRevision(second)

        #expect(try await journal.revisionCount(forArtifact: artifactID) == 1)
        #expect(try await journal.latestRevision(forArtifact: artifactID)?.id == second.id)
    }

    @Test("dropping one artifact ancestry leaves another artifact untouched")
    func droppingOneArtifactAncestryLeavesAnotherUntouched() async throws {
        let storage = InMemoryStorageProvider()
        let journal = StoredArtifactRevisionJournal(
            storage: storage, contentStore: StoredArtifactContentStore(storage: storage))
        let otherArtifact = ArtifactID()
        let kept = try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: otherArtifact, parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data("kept".utf8)),
                deviceID: deviceID, createdAt: Date(timeIntervalSince1970: 0)
            )
        )

        try await journal.recordRevision(kept)
        try await journal.recordRevision(try makeRevision(contents: "one"))
        try await journal.recordRevision(try makeRevision(contents: "two"))

        #expect(try await journal.revisionCount(forArtifact: otherArtifact) == 1)
    }
}

extension StoredArtifactRevisionJournalTests {
    @Test("the latest revision follows ancestry, not the clock")
    func theLatestRevisionFollowsAncestryNotTheClock() async throws {
        let storage = InMemoryStorageProvider()
        let journal = StoredArtifactRevisionJournal(
            storage: storage, contentStore: StoredArtifactContentStore(storage: storage))
        let older = try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: artifactID, parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data("one".utf8)),
                deviceID: deviceID, createdAt: Date(timeIntervalSince1970: 5_000)
            )
        )
        let newer = try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: artifactID, parentRevisionID: older.id,
                contentHash: ContentHash.digest(of: Data("two".utf8)),
                deviceID: deviceID, createdAt: Date(timeIntervalSince1970: 1)
            )
        )

        try await journal.recordRevision(older)
        try await journal.recordRevision(newer)

        #expect(try await journal.latestRevision(forArtifact: artifactID)?.id == newer.id)
    }

    @Test("retention that drops a revision drops its content with it")
    func retentionThatDropsARevisionDropsItsContentWithIt() async throws {
        let storage = InMemoryStorageProvider()
        let contentStore = StoredArtifactContentStore(storage: storage)
        let journal = StoredArtifactRevisionJournal(storage: storage, contentStore: contentStore)
        let superseded = try makeRevision(contents: "superseded")
        let latest = try makeRevision(contents: "latest")

        try await contentStore.storeContent(Data("superseded".utf8), forRevision: superseded.id)
        try await journal.recordRevision(superseded)
        try await contentStore.storeContent(Data("latest".utf8), forRevision: latest.id)
        try await journal.recordRevision(latest)

        #expect(try await contentStore.content(forRevision: superseded.id) == nil)
        #expect(try await contentStore.content(forRevision: latest.id) == Data("latest".utf8))
    }
}
