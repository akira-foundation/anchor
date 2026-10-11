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

@Suite("Context publication assembly")
struct ContextPublicationAssemblyTests {
    private let workspaceURL = URL(filePath: "/Users/dev/lighthouse")
    private let projectID = ProjectID()
    private let projectName = "Lighthouse Confidential"
    private let artifactNames = ["roadmap-confidential.md", "session-confidential.json"]
    private let summary = "Ship the sealed publication first"

    @Test("an assembled publication seals every object once under the published keys")
    func assembledPublicationSealsEveryObjectOnce() async throws {
        let localRootURL = FileManager.default.temporaryDirectory
            .appending(path: "anchor-publication-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: localRootURL) }
        let underlyingRemote = InMemoryStorageProvider()
        let storage = await ContextStorageAssembly.assemble(
            reachingRemote: { underlyingRemote }, localRootURL: localRootURL,
            key: SymmetricKey(size: .bits256))
        let database = try SQLiteDatabase(fileURL: nil)
        let seeded = try await seedProjectContext(in: database)
        let publication = try #require(
            ContextPublicationAssembly.makePublication(database: database, storage: storage))
        let request = PublishProjectContextRequest(workspaceURL: workspaceURL)

        let firstReport = try await publication.perform(request)
        let listingAfterFirst = try await underlyingRemote.listObjects(withPrefix: nil)
        let secondReport = try await publication.perform(request)
        let listingAfterSecond = try await underlyingRemote.listObjects(withPrefix: nil)

        var expectedKeys = [PublishedContextKeys.projectKey(for: projectID)]
        expectedKeys += seeded.artifactIDs.map { PublishedContextKeys.artifactKey(for: $0) }
        for source in seeded.sources {
            expectedKeys.append(
                try PublishedContextKeys.knowledgeKey(for: projectID, source: source))
        }
        #expect(firstReport.refusals.isEmpty)
        #expect(secondReport.refusals.isEmpty)
        #expect(Set(listingAfterFirst.map(\.key)) == Set(expectedKeys.compactMap { $0 }))
        #expect(listingAfterFirst.count == 5)
        #expect(listingAfterFirst.map(\.modifiedAt).max() == Date(timeIntervalSince1970: 5))
        #expect(listingAfterSecond == listingAfterFirst)
        for metadata in listingAfterSecond {
            let stored = try #require(try await underlyingRemote.object(for: metadata.key))
            let text = String(decoding: stored.object.contents, as: UTF8.self)
            for secret in [projectName, summary] + artifactNames {
                #expect(!text.contains(secret))
            }
        }
    }

    private func seedProjectContext(
        in database: SQLiteDatabase
    ) async throws -> (artifactIDs: [ArtifactID], sources: [KnowledgeEntrySource]) {
        let artifacts = try await SQLiteArtifactContextStore(database: database)
        let knowledge = try await SQLiteKnowledgeStore(database: database)
        try await artifacts.recordProjectContext(
            ProjectContext(
                projectID: projectID, displayName: projectName, canonicalRepositoryRemote: nil,
                workspaceURL: workspaceURL))
        var recordedArtifacts: [Artifact] = []
        for artifactName in artifactNames {
            let artifact = try #require(
                Artifact(
                    id: .derived(projectID: projectID, provider: .claude, name: artifactName),
                    projectID: projectID, provider: .claude, name: artifactName))
            let revision = try #require(
                ArtifactRevision(
                    id: RevisionID(), artifactID: artifact.id, parentRevisionID: nil,
                    contentHash: .digest(of: Data(artifactName.utf8)), deviceID: DeviceID(),
                    createdAt: Date(timeIntervalSince1970: 10), retention: artifact.retention))
            try await artifacts.indexArtifactRevisions([
                RecordedArtifactRevision(artifact: artifact, revision: revision)
            ])
            recordedArtifacts.append(artifact)
        }
        let currentSource = KnowledgeEntrySource.session(SessionID())
        try await knowledge.recordEntries(
            [makeEntry(summary, from: currentSource)], supersedingEntriesFrom: currentSource)
        let retiredSource = KnowledgeEntrySource.artifact(recordedArtifacts[0].id)
        try await knowledge.recordEntries(
            [makeEntry("Retired decision", from: retiredSource)],
            supersedingEntriesFrom: retiredSource)
        try await knowledge.recordEntries([], supersedingEntriesFrom: retiredSource)

        return (recordedArtifacts.map(\.id), [currentSource, retiredSource])
    }

    private func makeEntry(
        _ summaryText: String, from source: KnowledgeEntrySource
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: KnowledgeEntryID(), projectID: projectID, kind: .decision,
            summaryText: summaryText, source: source,
            sourceContentHash: .digest(of: Data(summaryText.utf8)),
            createdAt: Date(timeIntervalSince1970: 20))
    }
}
