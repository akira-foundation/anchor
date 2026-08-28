import AnchorApplication
import AnchorDomain
import AnchorSync
import Foundation

actor InMemoryRevisionJournal: ArtifactRevisionJournal {
    private(set) var recorded: [ArtifactRevision] = []
    private let failure: (any Error)?

    init(failing failure: (any Error)? = nil) {
        self.failure = failure
    }

    func latestRevision(forArtifact artifactID: ArtifactID) async throws -> ArtifactRevision? {
        let claimedParents = Set(recorded.compactMap(\.parentRevisionID))

        return recorded.last { $0.artifactID == artifactID && !claimedParents.contains($0.id) }
    }

    func revision(withIdentifier revisionID: RevisionID) async throws -> ArtifactRevision? {
        recorded.first { $0.id == revisionID }
    }

    func recordRevision(_ revision: ArtifactRevision) async throws {
        if let failure { throw failure }

        recorded.append(revision)
    }
}

actor InMemoryContentStore: ArtifactContentStore {
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

struct StubFailure: Error, Equatable {
    let isTransient: Bool
}

struct StubFailureClassifier: SyncFailureClassifying {
    func isWorthRetrying(_ failure: any Error) -> Bool {
        (failure as? StubFailure)?.isTransient ?? false
    }
}

func makeRevision(
    artifactID: ArtifactID = ArtifactID(),
    parent: RevisionID? = nil,
    contents: String
) throws -> ArtifactRevision {
    guard
        let revision = ArtifactRevision(
            id: RevisionID(),
            artifactID: artifactID,
            parentRevisionID: parent,
            contentHash: ContentHash.digest(of: Data(contents.utf8)),
            deviceID: DeviceID(),
            createdAt: Date(timeIntervalSince1970: 0)
        )
    else { throw StubFailure(isTransient: false) }

    return revision
}

actor StubRemoteRevisionFeed: RemoteRevisionFeed {
    private let pages: [String?: RemoteRevisionPage]

    init(pages: [String?: RemoteRevisionPage]) {
        self.pages = pages
    }

    func revisions(after cursor: String?) async throws -> RemoteRevisionPage {
        pages[cursor] ?? RemoteRevisionPage(revisions: [], cursor: nil)
    }
}

actor InMemorySyncCursorStore: SyncCursorStore {
    private var recorded: String?

    func cursor() async throws -> String? { recorded }

    func recordCursor(_ cursor: String) async throws { recorded = cursor }
}

actor InMemoryDivergenceJournal: ArtifactDivergenceJournal {
    private var recorded: [ArtifactDivergence] = []

    func recordDivergence(_ divergence: ArtifactDivergence) async throws {
        recorded.append(divergence)
    }

    func pendingDivergences() async throws -> [ArtifactDivergence] { recorded }
}
