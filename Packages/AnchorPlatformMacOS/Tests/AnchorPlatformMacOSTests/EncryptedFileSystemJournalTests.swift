import AnchorApplication
import AnchorDomain
import AnchorStorage
import CryptoKit
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("A revision written to encrypted files on this machine")
struct EncryptedFileSystemJournalTests {
    private func makeStorage() -> (any StorageProvider, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "anchor-\(UUID().uuidString)")

        return (
            EncryptingStorageProvider(
                wrapping: FileSystemStorageProvider(rootURL: root),
                key: SymmetricKey(size: .bits256)
            ),
            root
        )
    }

    private func makeRevision(artifactID: ArtifactID) throws -> ArtifactRevision {
        try #require(
            ArtifactRevision(
                id: RevisionID(),
                artifactID: artifactID,
                parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data("plan".utf8)),
                deviceID: DeviceID(),
                createdAt: Date(timeIntervalSince1970: 1_000)
            ))
    }

    @Test("a revision recorded on disk is the revision read back")
    func revisionRecordedOnDiskIsRevisionReadBack() async throws {
        let (storage, root) = makeStorage()
        defer { try? FileManager.default.removeItem(at: root) }

        let journal = StoredArtifactRevisionJournal(
            storage: storage, contentStore: StoredArtifactContentStore(storage: storage))
        let artifactID = ArtifactID()
        let revision = try makeRevision(artifactID: artifactID)

        try await journal.recordRevision(revision)

        #expect(try await journal.latestRevision(forArtifact: artifactID)?.id == revision.id)
    }

    @Test("content and revision both survive a recorder writing to disk")
    func contentAndRevisionBothSurviveRecorderWritingToDisk() async throws {
        let (storage, root) = makeStorage()
        defer { try? FileManager.default.removeItem(at: root) }

        let contentStore = StoredArtifactContentStore(storage: storage)
        let journal = StoredArtifactRevisionJournal(
            storage: storage, contentStore: contentStore)
        let content = Data("plan".utf8)
        let artifact = try #require(
            Artifact(
                id: ArtifactID(),
                projectID: ProjectID(),
                provider: .claude,
                name: "plans/00-indice.md"
            ))

        let recorded = try await ArtifactRevisionRecorder(
            journal: journal, contentStore: contentStore, deviceID: DeviceID()
        ).recordRevision(
            of: artifact, contentHash: ContentHash.digest(of: content), readingContent: { content })

        let revision = try #require(recorded)

        #expect(try await journal.latestRevision(forArtifact: artifact.id)?.id == revision.id)
        #expect(try await contentStore.content(forRevision: revision.id) == content)
    }
}
