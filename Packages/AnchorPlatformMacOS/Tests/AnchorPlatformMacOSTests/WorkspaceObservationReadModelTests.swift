import AnchorApplication
import AnchorDomain
import AnchorProvider
import AnchorStorage
import Foundation
import Testing

@testable import AnchorPlatformMacOS

extension WorkspaceObservationCoordinatorTests {
    @Test(
        "observation marks stale before source recording and checkpoints after indexing",
        arguments: [ReadModelRefusalStage.none, .artifact, .session])
    func observationOrdersReadModelUpdates(stage: ReadModelRefusalStage) async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "{}"])
        let checkpointURL = makeCheckpointURL()
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: checkpointURL.deletingLastPathComponent())
        }
        let checkpoint = ObservationCheckpointStore(fileURL: checkpointURL)
        try checkpoint.recordCheckpoint(50, forWorkspaceAt: workspace)
        let status = ContextReadModelStatusStore(
            supportDirectoryURL: checkpointURL.deletingLastPathComponent())
        let observer = FileSystemEventObserver.checkpointTestObserver()
        let discovery = CheckpointDiscoveryGate(
            discoverer: GraphifyArtifactProvider(workspaceURL: workspace), pausedAttempts: [1])
        var attempts = discovery.attempts.makeAsyncIterator()
        let index = ObservationIndexGate(refuses: stage == .artifact)
        var indexing = index.batches.makeAsyncIterator()
        let local = InMemoryStorageProvider()
        let remote = InMemoryStorageProvider()
        let (coordinator, _) = makeCoordinator(
            device: Device(id: DeviceID(), displayName: "Test", platform: .macOS),
            storage: local, checkpointStore: checkpoint, workspaceURL: workspace, remote: remote,
            observer: observer, discoverer: discovery, artifactIndex: index, contextStatus: status,
            sessionContext: ObservationSessionRefusal(refuses: stage == .session))
        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        await observer.deliverCheckpointTestChange(
            at: workspace.appending(path: "graphify-out/graph.json"), checkpoint: 100)
        #expect(await attempts.next() == 1)
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await status.requireAvailable()
        }
        #expect(try checkpoint.checkpoint(forWorkspaceAt: workspace) == 50)
        await discovery.resumeAttempt(1)
        let batch = try #require(await indexing.next())
        let revision = try #require(batch.first)
        let stored = try await StoredArtifactRevisionJournal(
            storage: local,
            contentStore: StoredArtifactContentStore(storage: local)
        ).latestRevision(forArtifact: revision.artifact.id)
        #expect(revision.revision == stored)
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await status.requireAvailable()
        }
        #expect(try checkpoint.checkpoint(forWorkspaceAt: workspace) == 50)
        await index.release()
        #expect(await publishedRevisionCount(in: remote, reaching: 1, within: .seconds(2)) == 1)
        #expect(try checkpoint.checkpoint(forWorkspaceAt: workspace) == 100)
        if stage != .none {
            await #expect(throws: ContextQueryFailure.contextUnavailable) {
                try await status.requireAvailable()
            }
            #expect(
                await coordinator.recordedRefusalCount == 1)
        } else {
            try await status.requireAvailable()
        }
        await coordinator.stopObserving()
    }
}

actor ObservationIndexGate: ArtifactContextIndexing {
    enum Failure: Error { case refused }
    nonisolated let batches: AsyncStream<[RecordedArtifactRevision]>
    private let continuation: AsyncStream<[RecordedArtifactRevision]>.Continuation
    private let refuses: Bool
    private var gate: CheckedContinuation<Void, Never>?

    init(refuses: Bool) {
        self.refuses = refuses
        let channel = AsyncStream<[RecordedArtifactRevision]>.makeStream()
        batches = channel.stream
        continuation = channel.continuation
    }
    func indexArtifactRevisions(_ revisions: [RecordedArtifactRevision]) async throws {
        await withCheckedContinuation { gate in
            self.gate = gate
            continuation.yield(revisions)
        }
        if refuses { throw Failure.refused }
    }
    func release() {
        gate?.resume()
        gate = nil
    }
}

enum ReadModelRefusalStage: Sendable { case none, artifact, session }

struct ObservationSessionRefusal: SessionContextRecording {
    let refuses: Bool
    func recordSessionContext(
        in revisions: [RecordedArtifactRevision], at instant: Date
    ) async -> [SessionContextRefusal] {
        guard refuses, let revision = revisions.first else { return [] }
        return [
            SessionContextRefusal(
                artifactName: revision.artifact.name, description: "missing content")
        ]
    }
}
