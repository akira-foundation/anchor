import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import AnchorStorage
import AnchorStoredContext
import CryptoKit
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Persistent publishable context reader")
struct PersistentPublishableContextReaderTests {
    private let workspaceURL = URL(filePath: "/Users/dev/anchor")
    private let projectID = ProjectID()

    @Test("reads the project, its artifacts and all of its knowledge")
    func readsProjectArtifactsAndKnowledge() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let artifacts = try await SQLiteArtifactContextStore(database: database)
        let knowledge = try await SQLiteKnowledgeStore(database: database)
        try await artifacts.recordProjectContext(
            ProjectContext(
                projectID: projectID, displayName: "Anchor", canonicalRepositoryRemote: nil,
                workspaceURL: workspaceURL))
        let artifact = try #require(
            Artifact(
                id: .derived(projectID: projectID, provider: .claude, name: "s.json"),
                projectID: projectID, provider: .claude, name: "s.json"))
        let revision = try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: artifact.id, parentRevisionID: nil,
                contentHash: .digest(of: Data("s".utf8)), deviceID: DeviceID(),
                createdAt: Date(timeIntervalSince1970: 10), retention: artifact.retention))
        try await artifacts.indexArtifactRevisions([
            RecordedArtifactRevision(artifact: artifact, revision: revision)
        ])
        let source = KnowledgeEntrySource.session(SessionID())
        let entry = KnowledgeEntry(
            id: KnowledgeEntryID(), projectID: projectID, kind: .todo, summaryText: "Ship 30",
            source: source, sourceContentHash: .digest(of: Data("s".utf8)),
            createdAt: Date(timeIntervalSince1970: 20))
        try await knowledge.recordEntries([entry], supersedingEntriesFrom: source)

        let context = try #require(
            try await PersistentPublishableContextReader(database: database)
                .loadPublishableProjectContext(forWorkspaceAt: workspaceURL))

        #expect(context.project.displayName == "Anchor")
        #expect(context.artifacts == [artifact])
        #expect(context.knowledgeEntries.map(\.id) == [entry.id])
    }

    @Test("an unknown workspace yields no context")
    func unknownWorkspaceYieldsNothing() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        _ = try await SQLiteArtifactContextStore(database: database)
        _ = try await SQLiteKnowledgeStore(database: database)

        let context = try await PersistentPublishableContextReader(database: database)
            .loadPublishableProjectContext(forWorkspaceAt: workspaceURL)

        #expect(context == nil)
    }

    @Test("local-only storage assembles no publication")
    func localOnlyStorageAssemblesNoPublication() async throws {
        let localRootURL = FileManager.default.temporaryDirectory
            .appending(path: "anchor-publication-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: localRootURL) }
        let storage = await ContextStorageAssembly.assemble(
            reachingRemote: { nil }, localRootURL: localRootURL,
            key: SymmetricKey(size: .bits256))

        let publication = ContextPublicationAssembly.makePublication(
            database: try SQLiteDatabase(fileURL: nil), storage: storage)

        #expect(publication.map { _ in true } == nil)
    }
}
