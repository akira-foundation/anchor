import AnchorApplication
import Foundation
import Synchronization
import Testing

@testable import AnchorPlatformMacOS

struct AgentConfigurationRecoveryFaultTests {
    private typealias Fixture = AgentConfigurationRecoveryStoreTests.Fixture
    private enum Interruption: Error { case stopped }

    @Test("absent cleanup publishes the nearest existing parent")
    func missingParentIsPublished() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let synchronizedParent = Mutex(false)
        let persistence = AgentBootstrapFilePersistence { checkpoint in
            if case .synchronizedDirectory(let directoryURL) = checkpoint,
                directoryURL.path == fixture.rootURL.path
            {
                synchronizedParent.withLock { $0 = true }
            }
        }
        try persistence.removeFile(
            fixture.rootURL.appendingPathComponent("missing/nested/temporary"))
        #expect(synchronizedParent.withLock { $0 })
    }

    @Test("non-directory parents cannot satisfy directory durability")
    func regularFileIsNotADurableDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("external".utf8).write(to: fixture.configurationURL)
        let persistence = AgentBootstrapFilePersistence()
        #expect(throws: (any Error).self) {
            try persistence.synchronizeDirectory(fixture.configurationURL)
        }
        #expect(throws: (any Error).self) {
            try persistence.removeFile(fixture.configurationURL.appendingPathComponent("temporary"))
        }
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("external".utf8))
    }

    @Test("a directory swapped into the deletion boundary preserves its contents")
    func deletionBoundaryPreservesDirectory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let transaction = try await fixture.begin()
        try Data("mutation".utf8).write(to: fixture.configurationURL)
        try await fixture.store.recordMutationState(for: transaction)
        let protectedURL = fixture.configurationURL.appendingPathComponent("external")
        let persistence = AgentBootstrapFilePersistence { checkpoint in
            if checkpoint == .removingFile(fixture.configurationURL) {
                try FileManager.default.removeItem(at: fixture.configurationURL)
                try FileManager.default.createDirectory(
                    at: fixture.configurationURL, withIntermediateDirectories: false)
                try Data("keep".utf8).write(to: protectedURL)
            }
        }
        let store = AgentConfigurationRecoveryStore(
            directoryURL: fixture.recoveryURL, persistence: persistence)
        await #expect(throws: (any Error).self) { try await store.restore(transaction) }
        #expect(FileManager.default.fileExists(atPath: protectedURL.path))
    }

    @Test("recovery recognizes restoration interrupted before cleanup", arguments: [true, false])
    func recoveryFinishesRestoredState(originalExists: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        if originalExists { try Data("original".utf8).write(to: fixture.configurationURL) }
        let transaction = try await fixture.begin()
        try Data("mutation".utf8).write(to: fixture.configurationURL)
        try await fixture.store.recordMutationState(for: transaction)
        if originalExists {
            try Data("original".utf8).write(to: fixture.configurationURL)
        } else {
            try FileManager.default.removeItem(at: fixture.configurationURL)
        }
        #expect(try await fixture.recover() == .restored)
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshotURL.path))
        #expect(try await fixture.recover() == .noTransaction)
    }

    @Test(
        "invalid persisted permissions are rejected before any update",
        arguments: [-1, 65536, Int.max])
    func invalidPermissionsRefused(permissions: Int) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("original".utf8).write(to: fixture.configurationURL)
        let transaction = try await fixture.begin()
        var manifest = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.manifestURL))
                as? [String: Any])
        manifest["originalPermissions"] = permissions
        try JSONSerialization.data(withJSONObject: manifest).write(to: fixture.manifestURL)
        await #expect(throws: (any Error).self) {
            try await fixture.store.recordMutationState(for: transaction)
        }
        await #expect(throws: (any Error).self) { try await fixture.store.restore(transaction) }
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("original".utf8))
    }

    @Test(
        "interrupted successful cleanup resumes without reverting configuration",
        arguments: ["snapshot", "manifest"])
    func interruptedCompletionResumes(boundary: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("original".utf8).write(to: fixture.configurationURL)
        let transaction = try await fixture.begin()
        try Data("configured".utf8).write(to: fixture.configurationURL)
        try await fixture.store.recordMutationState(for: transaction)
        let interruptionURL = boundary == "snapshot" ? fixture.snapshotURL : fixture.manifestURL
        let persistence = AgentBootstrapFilePersistence { checkpoint in
            if checkpoint == .removingFile(interruptionURL) { throw Interruption.stopped }
        }
        let store = AgentConfigurationRecoveryStore(
            directoryURL: fixture.recoveryURL, persistence: persistence)
        await #expect(throws: Interruption.self) { try await store.complete(transaction) }
        _ = try await fixture.recover()
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("configured".utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshotURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.manifestURL.path))
    }

    @Test("recovery cleans known orphan files while preserving unknown neighbors")
    func orphanPublicationIsCleaned() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let directoryURL = fixture.snapshotURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let pendingURL = directoryURL.appendingPathComponent(".\(UUID().uuidString).pending")
        let neighborURL = directoryURL.appendingPathComponent("unrelated.pending")
        for fileURL in [fixture.snapshotURL, pendingURL, neighborURL] {
            try Data("private".utf8).write(to: fileURL)
        }
        #expect(try await fixture.recover() == .noTransaction)
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshotURL.path))
        #expect(!FileManager.default.fileExists(atPath: pendingURL.path))
        #expect(FileManager.default.fileExists(atPath: neighborURL.path))
    }

    @Test("nested directory entries become durable before deeper directories or files")
    func directoryPublicationOrdering() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let firstURL = fixture.rootURL.appendingPathComponent("new")
        let secondURL = firstURL.appendingPathComponent("receipts")
        let checkpoints = Mutex<[String]>([])
        let persistence = AgentBootstrapFilePersistence { checkpoint in
            switch checkpoint {
            case .createdDirectory(let directoryURL):
                guard directoryURL.path.hasPrefix(fixture.rootURL.path) else { return }
                checkpoints.withLock { $0.append("create " + directoryURL.path) }
            case .synchronizedDirectory(let directoryURL):
                guard directoryURL.path.hasPrefix(fixture.rootURL.path) else { return }
                checkpoints.withLock { $0.append("sync " + directoryURL.path) }
            default: break
            }
        }
        let store = AgentBootstrapReceiptStore(directoryURL: secondURL, persistence: persistence)
        try await store.record(
            AgentBootstrapReceipt(
                client: .codex, configurationPath: "/config",
                definition: AgentMCPDefinition(command: "/anchor", arguments: [], environment: [:]))
        )
        #expect(
            checkpoints.withLock { Array($0.prefix(4)) } == [
                "create " + firstURL.path, "sync " + fixture.rootURL.path,
                "create " + secondURL.path, "sync " + firstURL.path,
            ])
        #expect(try fixture.permissions(at: firstURL) == 0o700)
        #expect(try fixture.permissions(at: secondURL) == 0o700)
    }

    @Test("retry repairs an interrupted parent directory publication")
    func retryPublishesExistingAncestors() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let firstURL = fixture.rootURL.appendingPathComponent("first")
        let leafURL = firstURL.appendingPathComponent("leaf")
        let interruptedPersistence = AgentBootstrapFilePersistence { checkpoint in
            if case .createdDirectory = checkpoint { throw Interruption.stopped }
        }
        #expect(throws: Interruption.self) { try interruptedPersistence.createDirectory(firstURL) }
        let synchronizedPaths = Mutex<[String]>([])
        let persistence = AgentBootstrapFilePersistence { checkpoint in
            if case .synchronizedDirectory(let directoryURL) = checkpoint {
                synchronizedPaths.withLock { $0.append(directoryURL.path) }
            }
        }
        try persistence.createDirectory(leafURL)
        #expect(
            synchronizedPaths.withLock { Array($0.suffix(2)) } == [
                fixture.rootURL.path, firstURL.path,
            ])
    }

    @Test("a directory durability failure prevents deeper publication")
    func directorySynchronizationFailureStopsReceipt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let firstURL = fixture.rootURL.appendingPathComponent("new")
        let receiptDirectoryURL = firstURL.appendingPathComponent("receipts")
        let persistence = AgentBootstrapFilePersistence { checkpoint in
            if case .synchronizedDirectory(let directoryURL) = checkpoint,
                directoryURL.path == fixture.rootURL.path
            {
                throw Interruption.stopped
            }
        }
        let store = AgentBootstrapReceiptStore(
            directoryURL: receiptDirectoryURL, persistence: persistence)
        await #expect(throws: Interruption.self) {
            try await store.record(
                AgentBootstrapReceipt(
                    client: .codex, configurationPath: "/config",
                    definition: AgentMCPDefinition(
                        command: "/anchor", arguments: [], environment: [:])))
        }
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        #expect(!FileManager.default.fileExists(atPath: receiptDirectoryURL.path))
    }

    @Test("retry makes restored configuration durable before cleanup", arguments: [true, false])
    func restoredStateIsPublishedBeforeCleanup(originalExists: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        if originalExists { try Data("original".utf8).write(to: fixture.configurationURL) }
        let transaction = try await fixture.begin()
        try Data("mutation".utf8).write(to: fixture.configurationURL)
        try await fixture.store.recordMutationState(for: transaction)
        let interruption = AgentBootstrapFilePersistence { checkpoint in
            if checkpoint == .renamedFile(fixture.configurationURL)
                || checkpoint == .removedFile(fixture.configurationURL)
            {
                throw CocoaError(.userCancelled)
            }
        }
        let interruptedStore = AgentConfigurationRecoveryStore(
            directoryURL: fixture.recoveryURL, persistence: interruption)
        await #expect(throws: (any Error).self) { try await interruptedStore.restore(transaction) }
        let synchronizedParent = Mutex(false)
        let persistence = AgentBootstrapFilePersistence { checkpoint in
            if case .synchronizedDirectory(let directoryURL) = checkpoint,
                directoryURL.path == fixture.rootURL.path
            {
                synchronizedParent.withLock { $0 = true }
            }
            if checkpoint == .removingFile(fixture.snapshotURL)
                || checkpoint == .removingFile(fixture.manifestURL)
            {
                #expect(synchronizedParent.withLock { $0 })
            }
        }
        let resumedStore = AgentConfigurationRecoveryStore(
            directoryURL: fixture.recoveryURL, persistence: persistence)
        #expect(
            try await resumedStore.recoverIncompleteTransaction(
                for: .claudeCode, configurationURL: fixture.configurationURL) == .restored)
        #expect(synchronizedParent.withLock { $0 })
    }

}
