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
        try await publisher.publishKnowledgeSnapshot(
            try #require(
                KnowledgeSourceSnapshot(projectID: projectID, source: source, entries: [entry])))

        let publishedObjects = try await plain.listObjects(withPrefix: nil)
        #expect(!publishedObjects.isEmpty)
        for metadata in publishedObjects {
            let stored = try #require(try await plain.object(for: metadata.key))
            let text = String(decoding: stored.object.contents, as: UTF8.self)
            #expect(!text.contains("Secret Project"))
            #expect(!text.contains(summary))
        }
    }

    private func descriptor(named displayName: String) -> PublishedProjectDescriptor {
        PublishedProjectDescriptor(
            projectID: projectID, displayName: displayName, canonicalRepositoryRemote: nil)
    }

    private func makeArtifact(name: String) -> Artifact? {
        Artifact(
            id: .derived(projectID: projectID, provider: .superpowers, name: name),
            projectID: projectID, provider: .superpowers, name: name)
    }
}

private actor PutCounter {
    private(set) var count = 0
    private var remainingFailures: Int

    init(failingFirstPuts: Int) {
        remainingFailures = failingFirstPuts
    }

    func increment() { count += 1 }

    func consumeFailure() -> Bool {
        guard remainingFailures > 0 else { return false }
        remainingFailures -= 1
        return true
    }
}

private struct CountingStorageProvider: StorageProvider {
    let wrapped: any StorageProvider
    let counter: PutCounter

    init(wrapping wrapped: any StorageProvider, failingFirstPuts: Int = 0) {
        self.wrapped = wrapped
        counter = PutCounter(failingFirstPuts: failingFirstPuts)
    }

    var putCount: Int {
        get async { await counter.count }
    }

    func putObject(
        _ storageObject: StorageObject, precondition: StorageWritePrecondition
    ) async throws(StorageFailure) -> StorageObjectMetadata {
        guard await !counter.consumeFailure() else { throw .transportUnavailable }
        let metadata = try await wrapped.putObject(storageObject, precondition: precondition)
        await counter.increment()
        return metadata
    }

    func object(for key: StorageKey) async throws(StorageFailure) -> StoredObject? {
        try await wrapped.object(for: key)
    }

    func deleteObject(for key: StorageKey) async throws(StorageFailure) {
        try await wrapped.deleteObject(for: key)
    }

    func listObjects(
        withPrefix prefix: StorageKey?
    ) async throws(StorageFailure) -> [StorageObjectMetadata] {
        try await wrapped.listObjects(withPrefix: prefix)
    }

    func observeChanges(
        after cursor: StorageCursor?
    ) -> AsyncThrowingStream<StorageChange, any Error> {
        wrapped.observeChanges(after: cursor)
    }
}
