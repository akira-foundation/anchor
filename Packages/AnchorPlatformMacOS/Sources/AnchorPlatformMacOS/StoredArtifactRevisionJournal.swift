import AnchorApplication
import AnchorDomain
import AnchorStorage
import Foundation

public struct StoredArtifactRevisionJournal: ArtifactRevisionJournal {
    private static let revisionsPrefix = "revisions"

    private let storage: any StorageProvider
    private let contentStore: any ArtifactContentStore

    public init(storage: any StorageProvider, contentStore: any ArtifactContentStore) {
        self.storage = storage
        self.contentStore = contentStore
    }

    public func latestRevision(forArtifact artifactID: ArtifactID) async throws -> ArtifactRevision?
    {
        let recorded = try await revisions(forArtifact: artifactID)
        let claimedParents = Set(recorded.compactMap(\.parentRevisionID))

        return recorded.first { !claimedParents.contains($0.id) }
    }

    public func recordRevision(_ revision: ArtifactRevision) async throws {
        let contents = try JSONEncoder().encode(revision)
        guard let key = storageKey(for: revision) else { return }

        try await storage.putObject(
            StorageObject(key: key, contents: contents), precondition: .none
        )

        guard revision.parentRevisionID == nil else { return }

        try await dropRevisions(
            forArtifact: revision.artifactID, exceptRevisionWithIdentifier: revision.id
        )
    }

    public func revisionCount(forArtifact artifactID: ArtifactID) async throws -> Int {
        try await revisions(forArtifact: artifactID).count
    }

    private func revisions(forArtifact artifactID: ArtifactID) async throws -> [ArtifactRevision] {
        guard let prefix = artifactPrefix(for: artifactID) else { return [] }

        var found: [ArtifactRevision] = []
        for metadata in try await storage.listObjects(withPrefix: prefix) {
            guard let stored = try await storage.object(for: metadata.key),
                let revision = try? JSONDecoder().decode(
                    ArtifactRevision.self, from: stored.object.contents
                )
            else {
                continue
            }
            found.append(revision)
        }

        return found
    }

    private func dropRevisions(
        forArtifact artifactID: ArtifactID,
        exceptRevisionWithIdentifier keptRevisionID: RevisionID
    ) async throws {
        for revision in try await revisions(forArtifact: artifactID)
        where revision.id != keptRevisionID {
            guard let key = storageKey(for: revision) else { continue }

            try await storage.deleteObject(for: key)
            try await contentStore.dropContent(forRevision: revision.id)
        }
    }

    private func artifactPrefix(for artifactID: ArtifactID) -> StorageKey? {
        StorageKey(rawValue: "\(Self.revisionsPrefix)/\(artifactID.rawValue)")
    }

    private func storageKey(for revision: ArtifactRevision) -> StorageKey? {
        StorageKey(
            rawValue:
                "\(Self.revisionsPrefix)/\(revision.artifactID.rawValue)/\(revision.id.rawValue)"
        )
    }
}
