import AnchorApplication
import AnchorDomain
import Foundation

actor RemoteRevisionReceiver {
    private let local: RevisionStore
    private let remote: RevisionStore
    private let feed: any RemoteRevisionFeed
    private let cursors: any SyncCursorStore
    private let divergences: any ArtifactDivergenceJournal
    private let now: @Sendable () -> Date

    init(
        local: RevisionStore,
        remote: RevisionStore,
        feed: any RemoteRevisionFeed,
        cursors: any SyncCursorStore,
        divergences: any ArtifactDivergenceJournal,
        now: @escaping @Sendable () -> Date
    ) {
        self.local = local
        self.remote = remote
        self.feed = feed
        self.cursors = cursors
        self.divergences = divergences
        self.now = now
    }

    func receiveRemoteRevisions() async throws {
        let page = try await feed.revisions(after: try await cursors.cursor())

        for revision in parentsBeforeChildren(page.revisions) {
            try await receive(revision)
        }

        guard let reached = page.cursor else { return }

        try await cursors.recordCursor(reached)
    }

    private func parentsBeforeChildren(
        _ revisions: [ArtifactRevision]
    ) -> [ArtifactRevision] {
        var remaining = revisions
        var ordered: [ArtifactRevision] = []
        var placed: Set<RevisionID> = []

        while !remaining.isEmpty {
            let ready = remaining.filter { revision in
                guard let parentID = revision.parentRevisionID else { return true }

                return placed.contains(parentID)
                    || !remaining.contains { candidate in candidate.id == parentID }
            }

            guard !ready.isEmpty else { return ordered + remaining }

            ordered += ready
            placed.formUnion(ready.map(\.id))
            remaining.removeAll { placed.contains($0.id) }
        }

        return ordered
    }

    private func receive(_ remoteRevision: ArtifactRevision) async throws {
        guard try await local.journal.revision(withIdentifier: remoteRevision.id) == nil,
            try await isUnseen(remoteRevision)
        else { return }

        let localLatest = try await local.journal.latestRevision(
            forArtifact: remoteRevision.artifactID)

        switch outcome(for: remoteRevision, against: localLatest) {
        case .apply:
            try await apply(remoteRevision)
        case .converged:
            try await record(remoteRevision, against: localLatest, as: .convergedOnIdenticalContent)
        case .conflict:
            try await preserve(remoteRevision)
            try await record(remoteRevision, against: localLatest, as: .awaitingDecision)
        }
    }

    private func apply(_ remoteRevision: ArtifactRevision) async throws {
        try await local.contents.storeContent(
            try await remoteContent(of: remoteRevision), forRevision: remoteRevision.id)
        try await local.journal.recordRevision(remoteRevision)
    }

    private func preserve(_ remoteRevision: ArtifactRevision) async throws {
        try await local.contents.storeContent(
            try await remoteContent(of: remoteRevision), forRevision: remoteRevision.id)
    }

    private func remoteContent(of remoteRevision: ArtifactRevision) async throws -> Data {
        guard let content = try await remote.contents.content(forRevision: remoteRevision.id) else {
            throw ArtifactSynchronizationFailure.revisionIsNoLongerHeldRemotely(remoteRevision.id)
        }

        return content
    }

    private func record(
        _ remoteRevision: ArtifactRevision,
        against localLatest: ArtifactRevision?,
        as resolution: ArtifactDivergenceResolution
    ) async throws {
        try await divergences.recordDivergence(
            ArtifactDivergence(
                artifactID: remoteRevision.artifactID,
                localRevisionID: localLatest?.id ?? remoteRevision.id,
                remoteRevisionID: remoteRevision.id,
                resolution: resolution,
                detectedAt: now()
            )
        )
    }

    private func isUnseen(_ remoteRevision: ArtifactRevision) async throws -> Bool {
        try await divergences.divergences()
            .contains { $0.remoteRevisionID == remoteRevision.id } == false
    }

    private func outcome(
        for remoteRevision: ArtifactRevision, against localLatest: ArtifactRevision?
    ) -> RemoteRevisionOutcome {
        guard let localLatest else { return .apply }
        guard remoteRevision.parentRevisionID != localLatest.id else { return .apply }
        guard remoteRevision.contentHash != localLatest.contentHash else { return .converged }

        return .conflict
    }
}

enum RemoteRevisionOutcome {
    case apply
    case converged
    case conflict
}
