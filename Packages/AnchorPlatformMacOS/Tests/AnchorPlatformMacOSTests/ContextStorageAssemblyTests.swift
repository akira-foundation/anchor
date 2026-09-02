import AnchorDomain
import AnchorStorage
import CryptoKit
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Where this machine keeps the context")
struct ContextStorageAssemblyTests {
    private let encryptionKey = SymmetricKey(size: .bits256)
    private let storageKey = StorageKey(rawValue: "context/secret.txt")!
    private let plaintext = Data("the quick brown fox".utf8)

    private func temporaryRootURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "anchor-\(UUID().uuidString)")
    }

    @Test("a machine that can reach the account keeps a copy on both sides")
    func machineThatCanReachAccountKeepsCopyOnBothSides() async throws {
        let root = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: root) }

        let assembled = await ContextStorageAssembly.assemble(
            reachingRemote: { InMemoryStorageProvider() }, localRootURL: root,
            key: encryptionKey)

        #expect(assembled.choice == .synchronized)
        #expect(assembled.remote != nil)
    }

    @Test("a machine that cannot reach the account still has somewhere to write")
    func machineThatCannotReachAccountStillHasSomewhereToWrite() async throws {
        let root = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: root) }

        let assembled = await ContextStorageAssembly.assemble(
            reachingRemote: { nil }, localRootURL: root, key: encryptionKey)

        #expect(assembled.choice == .localOnlyUntilAccountReturns)
        #expect(assembled.remote == nil)

        try await assembled.local.putObject(
            StorageObject(key: storageKey, contents: plaintext), precondition: .none)

        #expect(try await assembled.local.object(for: storageKey)?.object.contents == plaintext)
    }

    @Test("what travels to the account is never readable in the clear there")
    func whatTravelsToAccountIsNeverReadableInClearThere() async throws {
        let root = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: root) }

        let underneath = InMemoryStorageProvider()
        let assembled = await ContextStorageAssembly.assemble(
            reachingRemote: { underneath }, localRootURL: root, key: encryptionKey)
        let remote = try #require(assembled.remote)

        try await remote.putObject(
            StorageObject(key: storageKey, contents: plaintext), precondition: .none)

        let stored = try await underneath.object(for: storageKey)

        #expect(stored != nil)
        #expect(stored?.object.contents != plaintext)
        #expect(try await remote.object(for: storageKey)?.object.contents == plaintext)
    }

    @Test("what stays on this machine is never readable in the clear on disk")
    func whatStaysOnThisMachineIsNeverReadableInClearOnDisk() async throws {
        let root = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: root) }

        let assembled = await ContextStorageAssembly.assemble(
            reachingRemote: { nil }, localRootURL: root, key: encryptionKey)

        try await assembled.local.putObject(
            StorageObject(key: storageKey, contents: plaintext), precondition: .none)

        let onDisk =
            FileManager.default.enumerator(atPath: root.path(percentEncoded: false))?
            .compactMap { $0 as? String }
            .compactMap { try? Data(contentsOf: root.appending(path: $0)) } ?? []

        #expect(!onDisk.isEmpty)
        #expect(!onDisk.contains(plaintext))
    }
}

@Suite("The ports a machine without an account still needs")
struct DeferredContextPortsTests {
    @Test("a revision waiting to travel is not marked as travelled")
    func revisionWaitingToTravelIsNotMarkedAsTravelled() async throws {
        let storage = InMemoryStorageProvider()
        let journal = StoredSyncOperationJournal(storage: storage)
        let revision = try #require(
            ArtifactRevision(
                id: RevisionID(),
                artifactID: ArtifactID(),
                parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data("one".utf8)),
                deviceID: DeviceID(),
                createdAt: Date(timeIntervalSince1970: 1_000)
            ))
        _ = try await journal.queueOperation(
            for: revision, storageKey: StorageKey(rawValue: "artifacts/one")!)

        try await DeferredArtifactSynchronizer().synchronizePendingArtifactRevisions()

        #expect(try await journal.pendingOperations().count == 1)
    }

    @Test("a machine without an account announces itself to nobody rather than failing")
    func machineWithoutAccountAnnouncesItselfToNobodyRatherThanFailing() async throws {
        let projectID = ProjectID()
        let registry = DeferredDevicePresenceRegistry()

        try await registry.announcePresence(
            DevicePresence(projectID: projectID, deviceID: DeviceID(), lastSeenAt: Date()))

        #expect(try await registry.presences(onProject: projectID).isEmpty)
    }
}
