import AnchorApplication
import AnchorDomain
import AnchorStorage
import CryptoKit
import Foundation
import Testing

@testable import AnchorStoredContext

@Suite("Stored context publisher")
struct StoredContextPublisherTests {
    private let projectID = ProjectID()
    private let knowledgeSource = KnowledgeEntrySource.session(SessionID())

    @Test("publishing the same state twice writes the remote once")
    func republishingUnchangedStateWritesNothing() async throws {
        let remote = CountingStorageProvider(wrapping: InMemoryStorageProvider())
        let publisher = StoredContextPublisher(remote: remote, ledger: InMemoryStorageProvider())

        try await publisher.publishProjectDescriptor(descriptor(named: "Anchor"))
        try await publisher.publishProjectDescriptor(descriptor(named: "Anchor"))

        #expect(await remote.putCount == 1)
    }

    @Test("a changed project descriptor is written again")
    func changedProjectDescriptorIsRewritten() async throws {
        let remote = CountingStorageProvider(wrapping: InMemoryStorageProvider())
        let publisher = StoredContextPublisher(remote: remote, ledger: InMemoryStorageProvider())

        try await publisher.publishProjectDescriptor(descriptor(named: "Anchor"))
        try await publisher.publishProjectDescriptor(descriptor(named: "Anchor Renamed"))

        let projectKey = try #require(PublishedContextKeys.projectKey(for: projectID))
        let stored = try #require(try await remote.object(for: projectKey))
        let decoded = try PublishedContextCodec.decode(
            PublishedProjectDescriptor.self, from: stored.object.contents)
        #expect(await remote.putCount == 2)
        #expect(decoded.displayName == "Anchor Renamed")
    }

    @Test("a failed remote write is retried by the next publication")
    func failedRemoteWriteIsRetried() async throws {
        let remote = CountingStorageProvider(
            wrapping: InMemoryStorageProvider(), failingFirstPuts: 1)
        let publisher = StoredContextPublisher(remote: remote, ledger: InMemoryStorageProvider())

        await #expect(throws: StorageFailure.transportUnavailable) {
            try await publisher.publishProjectDescriptor(descriptor(named: "Anchor"))
        }
        try await publisher.publishProjectDescriptor(descriptor(named: "Anchor"))

        let projectKey = try #require(PublishedContextKeys.projectKey(for: projectID))
        #expect(await remote.putCount == 1)
        #expect(try await remote.object(for: projectKey) != nil)
    }

    @Test("an unchanged knowledge snapshot is written once")
    func unchangedKnowledgeSnapshotIsWrittenOnce() async throws {
        let remote = CountingStorageProvider(wrapping: InMemoryStorageProvider())
        let publisher = StoredContextPublisher(remote: remote, ledger: InMemoryStorageProvider())
        let snapshot = try #require(makeSnapshot(summaries: ["Cut releases from develop"]))

        try await publisher.publishKnowledgeSnapshot(snapshot)
        try await publisher.publishKnowledgeSnapshot(snapshot)

        #expect(await remote.putCount == 1)
    }

    @Test("a changed knowledge snapshot is written again")
    func changedKnowledgeSnapshotIsRewritten() async throws {
        let remote = CountingStorageProvider(wrapping: InMemoryStorageProvider())
        let publisher = StoredContextPublisher(remote: remote, ledger: InMemoryStorageProvider())
        let original = try #require(makeSnapshot(summaries: ["Cut releases from develop"]))
        let revised = try #require(makeSnapshot(summaries: []))

        try await publisher.publishKnowledgeSnapshot(original)
        try await publisher.publishKnowledgeSnapshot(revised)

        let knowledgeKey = try #require(
            try PublishedContextKeys.knowledgeKey(for: projectID, source: knowledgeSource))
        let stored = try #require(try await remote.object(for: knowledgeKey))
        let decoded = try PublishedContextCodec.decode(
            KnowledgeSourceSnapshot.self, from: stored.object.contents)
        #expect(await remote.putCount == 2)
        #expect(decoded.entries.isEmpty)
    }

    @Test("a publisher sharing the ledger and remote writes nothing already published")
    func publisherSharingLedgerWritesNothing() async throws {
        let sharedRemote = InMemoryStorageProvider()
        let sharedLedger = InMemoryStorageProvider()
        let artifact = try #require(makeArtifact(name: "plan.md"))
        let snapshot = try #require(makeSnapshot(summaries: ["Cut releases from develop"]))
        let firstPublisher = StoredContextPublisher(remote: sharedRemote, ledger: sharedLedger)
        try await firstPublisher.publishProjectDescriptor(descriptor(named: "Anchor"))
        try await firstPublisher.publishArtifactDescriptor(artifact)
        try await firstPublisher.publishKnowledgeSnapshot(snapshot)
        let counting = CountingStorageProvider(wrapping: sharedRemote)
        let secondPublisher = StoredContextPublisher(remote: counting, ledger: sharedLedger)

        try await secondPublisher.publishProjectDescriptor(descriptor(named: "Anchor"))
        try await secondPublisher.publishArtifactDescriptor(artifact)
        try await secondPublisher.publishKnowledgeSnapshot(snapshot)

        #expect(await counting.putCount == 0)
    }

    @Test("an artifact descriptor is written once")
    func artifactDescriptorIsWrittenOnce() async throws {
        let remote = CountingStorageProvider(wrapping: InMemoryStorageProvider())
        let publisher = StoredContextPublisher(remote: remote, ledger: InMemoryStorageProvider())
        let artifact = try #require(makeArtifact(name: "plan.md"))

        try await publisher.publishArtifactDescriptor(artifact)
        try await publisher.publishArtifactDescriptor(artifact)

        #expect(await remote.putCount == 1)
    }

    @Test("an artifact descriptor body carries only the published fields")
    func artifactDescriptorBodyCarriesOnlyPublishedFields() async throws {
        let remote = InMemoryStorageProvider()
        let publisher = StoredContextPublisher(remote: remote, ledger: InMemoryStorageProvider())
        let artifact = try #require(
            Artifact(
                id: .derived(projectID: projectID, provider: .claude, name: "session.jsonl"),
                projectID: projectID, provider: .claude, name: "session.jsonl",
                retention: .latestRevisionOnly))

        try await publisher.publishArtifactDescriptor(artifact)

        let artifactKey = try #require(PublishedContextKeys.artifactKey(for: artifact.id))
        let stored = try #require(try await remote.object(for: artifactKey))
        let envelope = try #require(
            try JSONSerialization.jsonObject(with: stored.object.contents) as? [String: Any])
        let body = try #require(envelope["body"] as? [String: Any])
        #expect(Set(body.keys) == ["artifactID", "projectID", "provider", "name"])
        #expect(body["artifactID"] as? String == artifact.id.rawValue)
    }

    @Test("an artifact descriptor written by another Mac counts as published")
    func existingArtifactDescriptorCountsAsPublished() async throws {
        let sharedRemote = InMemoryStorageProvider()
        let artifact = try #require(makeArtifact(name: "plan.md"))
        try await StoredContextPublisher(remote: sharedRemote, ledger: InMemoryStorageProvider())
            .publishArtifactDescriptor(artifact)
        let counting = CountingStorageProvider(wrapping: sharedRemote)
        let secondMac = StoredContextPublisher(remote: counting, ledger: InMemoryStorageProvider())

        try await secondMac.publishArtifactDescriptor(artifact)
        try await secondMac.publishArtifactDescriptor(artifact)

        #expect(await counting.putCount == 0)
    }

    @Test("an artifact whose identifier contradicts its name is refused")
    func contradictoryArtifactIsRefused() async throws {
        let publisher = StoredContextPublisher(
            remote: InMemoryStorageProvider(), ledger: InMemoryStorageProvider())
        let artifact = try #require(
            Artifact(id: ArtifactID(), projectID: projectID, provider: .codex, name: "plan.md"))

        await #expect(throws: StoredContextPublicationFailure.artifactIdentityMismatch(artifact.id))
        {
            try await publisher.publishArtifactDescriptor(artifact)
        }
    }

    @Test("an artifact identifier derived from another provider is refused")
    func artifactFromAnotherProviderIsRefused() async throws {
        let publisher = StoredContextPublisher(
            remote: InMemoryStorageProvider(), ledger: InMemoryStorageProvider())
        let artifact = try #require(
            Artifact(
                id: .derived(projectID: projectID, provider: .claude, name: "plan.md"),
                projectID: projectID, provider: .codex, name: "plan.md"))

        await #expect(throws: StoredContextPublicationFailure.artifactIdentityMismatch(artifact.id))
        {
            try await publisher.publishArtifactDescriptor(artifact)
        }
    }

    @Test("published objects are unreadable without the key")
    func publishedObjectsAreSealed() async throws {
        let plain = InMemoryStorageProvider()
        let sealed = EncryptingStorageProvider(wrapping: plain, key: SymmetricKey(size: .bits256))
        let publisher = StoredContextPublisher(remote: sealed, ledger: InMemoryStorageProvider())
        let source = KnowledgeEntrySource.session(SessionID())
        let summary = "Releases are cut from develop"
        let entry = KnowledgeEntry(
            id: KnowledgeEntryID(), projectID: projectID, kind: .decision, summaryText: summary,
            source: source, sourceContentHash: .digest(of: Data(summary.utf8)),
            createdAt: Date(timeIntervalSince1970: 1_000))

        try await publisher.publishProjectDescriptor(descriptor(named: "Secret Project"))
        try await publisher.publishArtifactDescriptor(
            try #require(makeArtifact(name: "secret-plan.md")))
        try await publisher.publishKnowledgeSnapshot(
            try #require(
                KnowledgeSourceSnapshot(projectID: projectID, source: source, entries: [entry])))

        let publishedObjects = try await plain.listObjects(withPrefix: nil)
        #expect(publishedObjects.count == 3)
        for metadata in publishedObjects {
            let stored = try #require(try await plain.object(for: metadata.key))
            let text = String(decoding: stored.object.contents, as: UTF8.self)
            #expect(!text.contains("Secret Project"))
            #expect(!text.contains("secret-plan.md"))
            #expect(!text.contains(summary))
        }
    }

    private func descriptor(named displayName: String) -> PublishedProjectDescriptor {
        PublishedProjectDescriptor(
            projectID: projectID, displayName: displayName, canonicalRepositoryRemote: nil)
    }

    private func makeSnapshot(summaries: [String]) -> KnowledgeSourceSnapshot? {
        KnowledgeSourceSnapshot(
            projectID: projectID, source: knowledgeSource,
            entries: summaries.map { summaryText in
                KnowledgeEntry(
                    id: KnowledgeEntryID(), projectID: projectID, kind: .decision,
                    summaryText: summaryText, source: knowledgeSource,
                    sourceContentHash: .digest(of: Data(summaryText.utf8)),
                    createdAt: Date(timeIntervalSince1970: 1_000))
            })
    }

    private func makeArtifact(name: String) -> Artifact? {
        Artifact(
            id: .derived(projectID: projectID, provider: .superpowers, name: name),
            projectID: projectID, provider: .superpowers, name: name)
    }
}
