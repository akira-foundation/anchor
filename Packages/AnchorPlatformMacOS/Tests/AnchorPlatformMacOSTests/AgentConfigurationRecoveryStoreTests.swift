import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct AgentConfigurationRecoveryStoreTests {
    @Test("rollback restores exact bytes and original POSIX permissions")
    func restoresBytesAndPermissions() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalBytes = Data([0, 255, 13, 10, 32])
        try originalBytes.write(to: fixture.configurationURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o640], ofItemAtPath: fixture.configurationURL.path)
        let transaction = try await fixture.begin()
        try Data("changed".utf8).write(to: fixture.configurationURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: fixture.configurationURL.path)
        try await fixture.store.recordMutationState(for: transaction)
        #expect(try await fixture.store.restore(transaction) == .restored)
        #expect(try Data(contentsOf: fixture.configurationURL) == originalBytes)
        #expect(try fixture.permissions(at: fixture.configurationURL) == 0o640)
        #expect(try await fixture.recover() == .noTransaction)
    }

    @Test("rollback removes a configuration that was originally absent")
    func restoresOriginalAbsence() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let transaction = try await fixture.begin()
        #expect(!transaction.originalExists)
        try Data().write(to: fixture.configurationURL)
        try await fixture.store.recordMutationState(for: transaction)
        #expect(try await fixture.store.restore(transaction) == .restored)
        #expect(!FileManager.default.fileExists(atPath: fixture.configurationURL.path))
    }

    @Test("snapshot exists with protected permissions before begin returns")
    func snapshotIsProtected() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("private configuration".utf8).write(to: fixture.configurationURL)
        _ = try await fixture.begin()
        #expect(try Data(contentsOf: fixture.snapshotURL) == Data("private configuration".utf8))
        #expect(try fixture.permissions(at: fixture.snapshotURL) == 0o600)
        #expect(try fixture.permissions(at: fixture.manifestURL) == 0o600)
    }

    @Test("successful completion removes recovery state and preserves the mutation")
    func completionCleansRecoveryState() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let transaction = try await fixture.begin()
        try Data("configured".utf8).write(to: fixture.configurationURL)
        try await fixture.store.recordMutationState(for: transaction)
        try await fixture.store.complete(transaction)
        #expect(try await fixture.recover() == .noTransaction)
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshotURL.path))
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("configured".utf8))
    }

    @Test("an interrupted removed definition is restored on the next launch")
    func incompleteTransactionRecoversOriginalConfiguration() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("original".utf8).write(to: fixture.configurationURL)
        let transaction = try await fixture.begin()
        try FileManager.default.removeItem(at: fixture.configurationURL)
        try await fixture.store.recordMutationState(for: transaction)
        #expect(try await fixture.recover() == .restored)
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("original".utf8))
    }

    @Test("rollback preserves a configuration changed after the recorded mutation")
    func rollbackRefusesConcurrentExternalEdit() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("original".utf8).write(to: fixture.configurationURL)
        let transaction = try await fixture.begin()
        try Data("mutation".utf8).write(to: fixture.configurationURL)
        try await fixture.store.recordMutationState(for: transaction)
        try Data("external".utf8).write(to: fixture.configurationURL)
        #expect(try await fixture.store.restore(transaction) == .configurationChangedExternally)
        #expect(try await fixture.recover() == .configurationChangedExternally)
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("external".utf8))
        #expect(try Data(contentsOf: fixture.snapshotURL) == Data("original".utf8))
    }

    @Test("a mutation interrupted before fingerprint recording is not overwritten")
    func unrecordedMutationRequiresRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let transaction = try await fixture.begin()
        try Data("unrecorded".utf8).write(to: fixture.configurationURL)
        #expect(try await fixture.store.restore(transaction) == .configurationChangedExternally)
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("unrecorded".utf8))
    }

    @Test(
        "corrupt and unsupported manifests cannot authorize rollback",
        arguments: ["broken", "unsupportedVersion"])
    func corruptManifestRefused(contents: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("original".utf8).write(to: fixture.configurationURL)
        let transaction = try await fixture.begin()
        try Data("mutation".utf8).write(to: fixture.configurationURL)
        try await fixture.store.recordMutationState(for: transaction)
        if contents == "unsupportedVersion" {
            var manifest = try #require(
                JSONSerialization.jsonObject(with: Data(contentsOf: fixture.manifestURL))
                    as? [String: Any])
            manifest["version"] = 999
            try JSONSerialization.data(withJSONObject: manifest).write(to: fixture.manifestURL)
        } else {
            try Data(contents.utf8).write(to: fixture.manifestURL)
        }
        await #expect(throws: (any Error).self) { try await fixture.recover() }
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("mutation".utf8))
    }

    @Test("corrupted snapshots are never restored")
    func corruptSnapshotRefused() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("original".utf8).write(to: fixture.configurationURL)
        let transaction = try await fixture.begin()
        try Data("mutation".utf8).write(to: fixture.configurationURL)
        try await fixture.store.recordMutationState(for: transaction)
        try Data("corrupt".utf8).write(to: fixture.snapshotURL)
        await #expect(throws: (any Error).self) { try await fixture.store.restore(transaction) }
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("mutation".utf8))
    }

    @Test("an incomplete transaction cannot be replaced or recovered for a different target")
    func transactionIsBoundToTarget() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try await fixture.begin()
        await #expect(throws: (any Error).self) { try await fixture.begin() }
        await #expect(throws: (any Error).self) {
            try await fixture.store.recoverIncompleteTransaction(
                for: .claudeCode, configurationURL: fixture.rootURL.appendingPathComponent("other"))
        }
    }

    @Test("stale transaction handles cannot change a newer transaction")
    func staleTransactionRefused() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalTransaction = try await fixture.begin()
        try await fixture.store.complete(originalTransaction)
        _ = try await fixture.begin()
        await #expect(throws: (any Error).self) {
            try await fixture.store.complete(originalTransaction)
        }
        await #expect(throws: (any Error).self) {
            try await fixture.store.recordMutationState(for: originalTransaction)
        }
    }

    @Test(
        "completion is terminal for retained handles",
        arguments: ["snapshotRestore", "manifestRestore", "snapshotComplete", "manifestComplete"])
    func completionCannotBeReopened(boundary: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("original".utf8).write(to: fixture.configurationURL)
        let transaction = try await fixture.begin()
        try Data("configured".utf8).write(to: fixture.configurationURL)
        try await fixture.store.recordMutationState(for: transaction)
        let boundaryURL = boundary.hasPrefix("snapshot") ? fixture.snapshotURL : fixture.manifestURL
        let persistence = AgentBootstrapFilePersistence { checkpoint in
            if checkpoint == .removingFile(boundaryURL) { throw CocoaError(.userCancelled) }
        }
        let interruptedStore = AgentConfigurationRecoveryStore(
            directoryURL: fixture.recoveryURL, persistence: persistence)
        await #expect(throws: (any Error).self) { try await interruptedStore.complete(transaction) }
        await #expect(throws: (any Error).self) {
            try await fixture.store.recordMutationState(for: transaction)
        }
        if boundary.hasSuffix("Complete") {
            try await fixture.store.complete(transaction)
        } else {
            #expect(try await fixture.store.restore(transaction) == .noTransaction)
        }
        try await fixture.store.complete(transaction)
        try await fixture.store.complete(transaction)
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("configured".utf8))
        #expect(try await fixture.recover() == .noTransaction)
    }

    @Test(
        "interrupted restoration removes only its transaction temporary file",
        arguments: ["recover", "restore", "complete"])
    func restorationTemporaryIsRecovered(entryPoint: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("original".utf8).write(to: fixture.configurationURL)
        let transaction = try await fixture.begin()
        try Data("mutation".utf8).write(to: fixture.configurationURL)
        try await fixture.store.recordMutationState(for: transaction)
        let expectedURL = fixture.rootURL.appendingPathComponent(
            ".anchor-recovery-\(transaction.identifier.uuidString).pending")
        let neighborURL = fixture.rootURL.appendingPathComponent(".\(UUID().uuidString).pending")
        try Data("neighbor".utf8).write(to: neighborURL)
        let persistence = AgentBootstrapFilePersistence { checkpoint in
            if case .preparedFile(let fileURL) = checkpoint,
                fileURL.deletingLastPathComponent().path == fixture.rootURL.path
            {
                #expect(fileURL.path == expectedURL.path)
                throw CocoaError(.userCancelled)
            }
        }
        let interruptedStore = AgentConfigurationRecoveryStore(
            directoryURL: fixture.recoveryURL, persistence: persistence)
        await #expect(throws: (any Error).self) { try await interruptedStore.restore(transaction) }
        #expect(FileManager.default.fileExists(atPath: expectedURL.path))
        switch entryPoint {
        case "recover": #expect(try await fixture.recover() == .restored)
        case "restore": #expect(try await fixture.store.restore(transaction) == .restored)
        default: try await fixture.store.complete(transaction)
        }
        #expect(!FileManager.default.fileExists(atPath: expectedURL.path))
        #expect(try Data(contentsOf: neighborURL) == Data("neighbor".utf8))
        let expectedContents = entryPoint == "complete" ? "mutation" : "original"
        #expect(try Data(contentsOf: fixture.configurationURL) == Data(expectedContents.utf8))
    }

    struct Fixture {
        let rootURL: URL
        let configurationURL: URL
        let recoveryURL: URL
        let store: AgentConfigurationRecoveryStore
        var manifestURL: URL { recoveryURL.appendingPathComponent("claudeCode/manifest.json") }
        var snapshotURL: URL { recoveryURL.appendingPathComponent("claudeCode/snapshot") }

        init() throws {
            rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString)
            configurationURL = rootURL.appendingPathComponent("configuration")
            recoveryURL = rootURL.appendingPathComponent("recovery")
            store = AgentConfigurationRecoveryStore(directoryURL: recoveryURL)
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        func begin() async throws -> AgentConfigurationRecoveryTransaction {
            try await store.begin(client: .claudeCode, configurationURL: configurationURL)
        }

        func recover() async throws -> AgentConfigurationRecoveryResult {
            try await AgentConfigurationRecoveryStore(directoryURL: recoveryURL)
                .recoverIncompleteTransaction(for: .claudeCode, configurationURL: configurationURL)
        }

        func permissions(at fileURL: URL) throws -> Int {
            try #require(
                FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions]
                    as? Int)
        }

        func remove() { try? FileManager.default.removeItem(at: rootURL) }
    }
}
