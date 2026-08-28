import AnchorApplication
import AnchorDomain
import AnchorSync
import Foundation
import Testing

@Suite("Receiving revisions from the other side")
struct ArtifactSynchronizerReceiveTests {
    private let cursors = InMemorySyncCursorStore()
    private let divergences = InMemoryDivergenceJournal()

    private func makeSynchronizer(
        local: RevisionStore,
        remote: RevisionStore,
        feed: StubRemoteRevisionFeed
    ) -> ArtifactSynchronizer {
        ArtifactSynchronizer(
            local: local,
            remote: remote,
            operations: AppendOnlySyncOperationJournal(),
            failures: StubFailureClassifier(),
            feed: feed,
            cursors: cursors,
            divergences: divergences,
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    private func makeStore() -> RevisionStore {
        RevisionStore(journal: InMemoryRevisionJournal(), contents: InMemoryContentStore())
    }

    private func publish(
        _ revision: ArtifactRevision, contents: String, to remote: RevisionStore
    ) async throws {
        try await remote.contents.storeContent(Data(contents.utf8), forRevision: revision.id)
        try await remote.journal.recordRevision(revision)
    }

    @Test("a revision this machine has never seen arrives with its contents")
    func aRevisionThisMachineHasNeverSeenArrivesWithItsContents() async throws {
        let local = makeStore()
        let remote = makeStore()
        let revision = try makeRevision(contents: "from the other mac")
        try await publish(revision, contents: "from the other mac", to: remote)

        try await makeSynchronizer(
            local: local, remote: remote,
            feed: StubRemoteRevisionFeed(
                pages: [nil: RemoteRevisionPage(revisions: [revision], cursor: "page-1")])
        ).synchronizePendingArtifactRevisions()

        #expect(try await local.journal.revision(withIdentifier: revision.id) == revision)
        #expect(
            try await local.contents.content(forRevision: revision.id)
                == Data("from the other mac".utf8))
    }

    @Test("a revision that continues the local history is taken")
    func aRevisionThatContinuesTheLocalHistoryIsTaken() async throws {
        let local = makeStore()
        let remote = makeStore()
        let artifactID = ArtifactID()
        let base = try makeRevision(artifactID: artifactID, contents: "base")
        try await local.journal.recordRevision(base)
        let next = try makeRevision(artifactID: artifactID, parent: base.id, contents: "next")
        try await publish(next, contents: "next", to: remote)

        try await makeSynchronizer(
            local: local, remote: remote,
            feed: StubRemoteRevisionFeed(
                pages: [nil: RemoteRevisionPage(revisions: [next], cursor: "page-1")])
        ).synchronizePendingArtifactRevisions()

        #expect(try await local.journal.revision(withIdentifier: next.id) == next)
        #expect(try await divergences.pendingDivergences().isEmpty)
    }

    @Test("a revision that forks the local history is recorded and not applied")
    func aRevisionThatForksTheLocalHistoryIsRecordedAndNotApplied() async throws {
        let local = makeStore()
        let remote = makeStore()
        let artifactID = ArtifactID()
        let base = try makeRevision(artifactID: artifactID, contents: "base")
        let ours = try makeRevision(artifactID: artifactID, parent: base.id, contents: "ours")
        try await local.journal.recordRevision(base)
        try await local.journal.recordRevision(ours)
        let theirs = try makeRevision(artifactID: artifactID, parent: base.id, contents: "theirs")
        try await publish(theirs, contents: "theirs", to: remote)

        try await makeSynchronizer(
            local: local, remote: remote,
            feed: StubRemoteRevisionFeed(
                pages: [nil: RemoteRevisionPage(revisions: [theirs], cursor: "page-1")])
        ).synchronizePendingArtifactRevisions()

        #expect(try await local.journal.revision(withIdentifier: theirs.id) == nil)

        let recorded = try #require(try await divergences.pendingDivergences().first)

        #expect(recorded.artifactID == artifactID)
        #expect(recorded.localRevisionID == ours.id)
        #expect(recorded.remoteRevisionID == theirs.id)
    }

    @Test("a revision already held locally is not taken twice")
    func aRevisionAlreadyHeldLocallyIsNotTakenTwice() async throws {
        let local = makeStore()
        let remote = makeStore()
        let revision = try makeRevision(contents: "same")
        try await local.journal.recordRevision(revision)
        try await publish(revision, contents: "same", to: remote)

        try await makeSynchronizer(
            local: local, remote: remote,
            feed: StubRemoteRevisionFeed(
                pages: [nil: RemoteRevisionPage(revisions: [revision], cursor: "page-1")])
        ).synchronizePendingArtifactRevisions()

        #expect(try await local.contents.content(forRevision: revision.id) == nil)
    }

    @Test("the next run resumes where the last one stopped")
    func theNextRunResumesWhereTheLastOneStopped() async throws {
        let local = makeStore()
        let remote = makeStore()
        let first = try makeRevision(contents: "first")
        let second = try makeRevision(contents: "second")
        try await publish(first, contents: "first", to: remote)
        try await publish(second, contents: "second", to: remote)
        let feed = StubRemoteRevisionFeed(
            pages: [
                nil: RemoteRevisionPage(revisions: [first], cursor: "page-1"),
                "page-1": RemoteRevisionPage(revisions: [second], cursor: "page-2"),
            ]
        )

        try await makeSynchronizer(local: local, remote: remote, feed: feed)
            .synchronizePendingArtifactRevisions()
        try await makeSynchronizer(local: local, remote: remote, feed: feed)
            .synchronizePendingArtifactRevisions()

        #expect(try await local.journal.revision(withIdentifier: second.id) == second)
        #expect(try await cursors.cursor() == "page-2")
    }

    @Test("a child that arrives before its parent is still applied after it")
    func aChildThatArrivesBeforeItsParentIsStillAppliedAfterIt() async throws {
        let local = makeStore()
        let remote = makeStore()
        let artifactID = ArtifactID()
        let parent = try makeRevision(artifactID: artifactID, contents: "parent")
        let child = try makeRevision(artifactID: artifactID, parent: parent.id, contents: "child")
        try await publish(parent, contents: "parent", to: remote)
        try await publish(child, contents: "child", to: remote)

        try await makeSynchronizer(
            local: local, remote: remote,
            feed: StubRemoteRevisionFeed(
                pages: [nil: RemoteRevisionPage(revisions: [child, parent], cursor: "page-1")])
        ).synchronizePendingArtifactRevisions()

        #expect(try await local.journal.revision(withIdentifier: child.id) == child)
        #expect(try await divergences.pendingDivergences().isEmpty)
    }
}
