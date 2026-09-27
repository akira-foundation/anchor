import AnchorApplication
import AnchorDomain
import AnchorPersistence
import AnchorProvider
import AnchorSearch
import AnchorStorage
import CryptoKit
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Persistent context read-model assembly")
struct ContextReadModelAssemblyTests {
    @Test("opening the writer migrates and exposes the presence snapshot")
    func writerExposesPresenceSnapshot() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let presence = DevicePresence(
            projectID: fixture.observed.projectID,
            deviceID: DeviceID.derived(fromSeed: "writer-presence"),
            lastSeenAt: Date(timeIntervalSince1970: 50))

        try await writer.presences.recordPresence(presence)

        #expect(
            try await writer.presences.presences(onProject: fixture.observed.projectID)
                == [presence])
    }

    @Test("rebuild refreshes remote presence into the durable snapshot")
    func rebuildRefreshesRemotePresence() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let storage = await fixture.storage()
        let remotePresence = DevicePresence(
            projectID: fixture.observed.projectID,
            deviceID: DeviceID.derived(fromSeed: "remote-presence"),
            lastSeenAt: Date(timeIntervalSince1970: 60))
        let rebuilder = try await fixture.rebuilder(
            writer: writer, storage: storage,
            presenceRemote: RebuildPresenceRegistry(presences: [remotePresence]))

        _ = try await rebuilder.rebuild()

        #expect(
            try await writer.presences.presences(onProject: fixture.observed.projectID)
                == [remotePresence])
    }

    @Test("failed remote presence refresh preserves cached rows and completes rebuild")
    func rebuildPreservesPresenceWhenRemoteFails() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let storage = await fixture.storage()
        let cachedPresence = DevicePresence(
            projectID: fixture.observed.projectID,
            deviceID: DeviceID.derived(fromSeed: "cached-presence"),
            lastSeenAt: Date(timeIntervalSince1970: 70))
        try await writer.presences.recordPresence(cachedPresence)
        let rebuilder = try await fixture.rebuilder(
            writer: writer, storage: storage,
            presenceRemote: RebuildPresenceRegistry(fails: true))

        #expect(try await rebuilder.rebuild() == 1)
        #expect(
            try await writer.presences.presences(onProject: fixture.observed.projectID)
                == [cachedPresence])
    }

    @Test("the app and helper resolve the same context database URL")
    func appAndHelperShareTheContextDatabaseLocation() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let reader = try await fixture.reader()
        #expect(writer.databaseURL == fixture.support.appending(path: "context.sqlite"))
        #expect(reader.databaseURL == writer.databaseURL)
        #expect(await fixture.keyLoads.count == 0)
    }

    @Test("a relative requested workspace is refused")
    func relativeWorkspaceIsRefused() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        await #expect(throws: ContextQueryFailure.workspaceNotAuthorized) {
            try await fixture.reader(requestedPath: "workspace")
        }
    }

    @Test("a different absolute workspace is refused")
    func differentWorkspaceIsRefused() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        await #expect(throws: ContextQueryFailure.workspaceNotAuthorized) {
            try await fixture.reader(requestedPath: fixture.root.path())
        }
    }

    @Test("artifact content reads require an existing key without creating one")
    func artifactContentRequiresAnExistingEncryptionKey() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let seeded = try await fixture.seed()
        let reader = try await fixture.reader()
        #expect(
            try await reader.currentProject.perform(ProjectContextRequest()).projectID
                == fixture.observed.projectID)
        #expect(
            try await reader.listArtifacts.perform(try #require(ListProjectArtifactsRequest()))
                .records.count == 1)
        #expect(
            try await reader.listSessions.perform(try #require(ListProjectSessionsRequest()))
                .records.count == 1)
        #expect(
            try await reader.search.perform(
                try #require(SearchProjectContextRequest(text: "checkpoint"))
            ).records.count == 1)
        #expect(await fixture.keyLoads.count == 0)
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await reader.readArtifact.perform(
                try #require(ReadProjectArtifactRequest(artifactID: seeded.artifact.id)))
        }
        #expect(await fixture.keyLoads.count == 1)
        let unlocked = try await fixture.reader(key: fixture.key)
        let chunk = try await unlocked.readArtifact.perform(
            try #require(ReadProjectArtifactRequest(artifactID: seeded.artifact.id)))
        #expect(chunk.text == "unchanged plan")
    }

    @Test("reopening the assembly preserves indexed sessions")
    func reopeningAssemblyPreservesIndexedSessions() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        _ = try await fixture.seed()
        let reader = try await fixture.reader()
        let reopened = try await fixture.reader()
        let first = try await reader.listSessions.perform(
            try #require(ListProjectSessionsRequest()))
        let second = try await reopened.listSessions.perform(
            try #require(ListProjectSessionsRequest()))
        #expect(first == second)
        #expect(second.records.first?.session.id == fixture.transcript.session.id)
        let entries = try await reopened.readMessages.perform(
            try #require(ReadSessionMessagesRequest(sessionID: fixture.transcript.session.id)))
        #expect(entries.records == fixture.transcript.entries)
        let resume = try await reopened.resume.perform(ProjectContextRequest())
        #expect(resume.recentSession?.session == fixture.transcript.session)
    }

    @Test("a stale read model is refused until an idempotent rebuild completes")
    func staleReadModelIsUnavailableUntilRebuilt() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let reader = try await fixture.reader()
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await reader.currentProject.perform(ProjectContextRequest())
        }
        let storage = await fixture.storage()
        let rebuilder = try await fixture.rebuilder(writer: writer, storage: storage)
        _ = try await rebuilder.rebuild()
        _ = try await rebuilder.rebuild()
        #expect(
            try await reader.listSessions.perform(try #require(ListProjectSessionsRequest()))
                .records.count == 1)
        let update = try await writer.status.beginUpdate()
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await reader.search.perform(
                try #require(SearchProjectContextRequest(text: "checkpoint")))
        }
        try await writer.status.completeUpdate(update, succeeded: false)
        let later = try await writer.status.beginUpdate()
        try await writer.status.completeUpdate(later, succeeded: true)
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await reader.listSessions.perform(try #require(ListProjectSessionsRequest()))
        }
        _ = try await rebuilder.rebuild()
        #expect(
            try await reader.currentProject.perform(ProjectContextRequest())
                .canonicalRepositoryRemote == nil)
    }

    @Test("rebuilding discovers unchanged artifacts and uses journal timestamps")
    func rebuildIndexesCurrentArtifactRevisions() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let seeded = try await fixture.seed()
        let reader = try await fixture.reader()
        let request = try #require(ListProjectArtifactsRequest())
        let page = try await reader.listArtifacts.perform(request)
        let record = try #require(page.records.first)
        #expect(record.latestRevision?.id == seeded.revision.id)
        #expect(record.latestRevision?.createdAt == Date(timeIntervalSince1970: 123.125))
        #expect(record.artifact == seeded.artifact)
    }

    @Test("missing read models stay unavailable without creating a database or loading a key")
    func missingReadModelDoesNotCreateStorage() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let reader = try await fixture.reader()
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await reader.currentProject.perform(ProjectContextRequest())
        }
        #expect(!FileManager.default.fileExists(atPath: reader.databaseURL.path()))
        #expect(await fixture.keyLoads.count == 0)
    }

    @Test("rebuild failures preserve the marker and the last complete batches")
    func failedRebuildRemainsUnavailable() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let storage = await fixture.storage()
        let rebuilder = try await fixture.rebuilder(writer: writer, storage: storage, failing: true)
        await #expect(throws: (any Error).self) { try await rebuilder.rebuild() }
        let reader = try await fixture.reader()
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await reader.currentProject.perform(ProjectContextRequest())
        }
    }
}

private struct RebuildPresenceRegistry: DevicePresenceRegistry {
    enum Failure: Error { case unavailable }

    let returnedPresences: [DevicePresence]
    let fails: Bool

    init(presences: [DevicePresence] = [], fails: Bool = false) {
        returnedPresences = presences
        self.fails = fails
    }

    func announcePresence(_ presence: DevicePresence) async throws {}

    func presences(onProject projectID: ProjectID) async throws -> [DevicePresence] {
        if fails { throw Failure.unavailable }
        return returnedPresences
    }
}
