import AnchorApplication
import AnchorDomain
import AnchorProvider
import AnchorSearch
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Exclusive context reconstruction")
struct ContextRebuildExclusivityTests {
    @Test("an update arriving after R1 capture publishes R2 only after replacement")
    func queuedRevisionSurvivesReplacement() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let first = try await fixture.seed()
        let writer = try await fixture.writer()
        let storage = await fixture.storage()
        let captured = RebuildInterleavingGate()
        let replacement = RebuildInterleavingGate()
        let ordinaryFinished = RebuildInterleavingGate()
        let rebuild = ContextReadModelRebuilder(
            projectID: fixture.observed.projectID,
            discoverer: SuperpowersArtifactProvider(workspaceURL: fixture.observed.workspaceURL),
            journal: StoredArtifactRevisionJournal(
                storage: storage.local,
                contentStore: StoredArtifactContentStore(storage: storage.local)),
            artifacts: writer.artifacts,
            transcripts: try await SQLiteContextSearch(database: writer.database),
            canonicalSessions: {
                await captured.open()
                await replacement.wait()
                return []
            }, status: writer.status)
        let rebuilding = Task { try await rebuild.rebuild() }
        await captured.wait()
        let second = try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: first.artifact.id,
                parentRevisionID: first.revision.id,
                contentHash: ContentHash.digest(of: Data("R2".utf8)),
                deviceID: first.revision.deviceID,
                createdAt: Date(timeIntervalSince1970: 124)))
        let ordinary = Task {
            let update = try await writer.status.beginUpdate()
            try await writer.artifacts.indexArtifactRevisions([
                RecordedArtifactRevision(artifact: first.artifact, revision: second)
            ])
            try await writer.status.completeUpdate(update, succeeded: true)
            await ordinaryFinished.open()
        }
        while await writer.status.pendingUpdates.isEmpty {
            if await ordinaryFinished.isOpen { break }
            await Task.yield()
        }
        #expect(await ordinaryFinished.isOpen == false)
        await replacement.open()
        _ = try await rebuilding.value
        try await ordinary.value
        let reader = try await fixture.reader()
        let page = try await reader.listArtifacts.perform(
            try #require(ListProjectArtifactsRequest()))
        #expect(page.records.first?.latestRevision?.id == second.id)
    }

    @Test("cancelling an update queued behind rebuild does not strand availability")
    func cancelledQueuedUpdateDoesNotBlockRebuild() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let status = ContextReadModelStatusStore(supportDirectoryURL: fixture.support)
        let rebuild = try await status.beginUpdate(rebuilding: true)
        let queued = Task { try await status.beginUpdate() }
        while await status.pendingUpdates.isEmpty { await Task.yield() }
        queued.cancel()
        await #expect(throws: CancellationError.self) { try await queued.value }
        try await status.completeUpdate(rebuild, succeeded: true)
        try await status.requireAvailable()
        #expect(await status.pendingUpdates.isEmpty)
    }
}

private actor RebuildInterleavingGate {
    private(set) var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting.removeAll()
    }
}
