import AnchorApplication
import Foundation
import Synchronization
import Testing

@testable import AnchorPlatformMacOS

struct AgentBootstrapReceiptTransitionTests {
    @Test("receipt deletion replay synchronizes its directory before deleting the journal")
    func receiptDeletionReplayIsDurable() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let receiptDirectory = fixture.directory.appendingPathComponent("receipts")
        let receiptURL = receiptDirectory.appendingPathComponent("claudeCode.json")
        let journalURL = receiptDirectory.appendingPathComponent("transitions/claudeCode.json")
        let transaction = try await fixture.recovery.begin(
            client: .claudeCode, configurationURL: fixture.configurationURL)
        try await fixture.receipts.beginTransition(
            transaction, previousReceipt: nil, desiredReceipt: desiredReceipt(fixture))
        try await fixture.receipts.record(desiredReceipt(fixture))
        try await fixture.receipts.markRollback(transaction)
        let interruptedReceipts = AgentBootstrapReceiptStore(
            directoryURL: receiptDirectory,
            persistence: AgentBootstrapFilePersistence { checkpoint in
                if case .removedFile(let fileURL) = checkpoint, fileURL.path == receiptURL.path {
                    throw ClaudeFakeFailure.secret
                }
            })
        await #expect(throws: (any Error).self) {
            try await interruptedReceipts.finishTransition(transaction)
        }
        #expect(!FileManager.default.fileExists(atPath: receiptURL.path))
        let receiptDirectorySynchronized = Mutex(false)
        let resumedReceipts = AgentBootstrapReceiptStore(
            directoryURL: receiptDirectory,
            persistence: AgentBootstrapFilePersistence { checkpoint in
                if case .synchronizedDirectory(let directoryURL) = checkpoint,
                    directoryURL.path == receiptDirectory.path
                {
                    receiptDirectorySynchronized.withLock { $0 = true }
                }
                if case .removingFile(let fileURL) = checkpoint, fileURL.path == journalURL.path {
                    #expect(receiptDirectorySynchronized.withLock { $0 })
                }
            })
        try await resumedReceipts.finishTransition(transaction)
        #expect(receiptDirectorySynchronized.withLock { $0 })
        #expect(!FileManager.default.fileExists(atPath: journalURL.path))
    }

    @Test("interrupted first registration restores original absence without leaving ownership")
    func firstRegistrationInterrupted() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let transaction = try await fixture.recovery.begin(
            client: .claudeCode, configurationURL: fixture.configurationURL)
        try await fixture.receipts.beginTransition(
            transaction, previousReceipt: nil, desiredReceipt: desiredReceipt(fixture))
        try fixture.write(fixture.registration.definition)
        try await fixture.recovery.recordMutationState(for: transaction)
        try await fixture.receipts.record(desiredReceipt(fixture))
        #expect(
            try await fixture.receipts.recoverConfigurationAndReceipt(
                for: .claudeCode, configurationURL: fixture.configurationURL,
                recovery: fixture.recovery) == .restored)
        #expect(try await fixture.receipts.load(for: .claudeCode) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.configurationURL.path))
    }

    @Test("driver recovers interrupted ownership publication before a managed update")
    func driverRecoversReceiptAndConfiguration() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let transaction = try await prepareTransition(fixture)
        try fixture.write(fixture.registration.definition)
        try await fixture.recovery.recordMutationState(for: transaction)
        try await fixture.receipts.record(desiredReceipt(fixture))
        await fixture.runner.append { _ in
            try fixture.write(nil)
            return 0
        }
        await fixture.runner.append { _ in
            try fixture.write(fixture.registration.definition)
            return 0
        }
        #expect(await fixture.driver().ensureUserRegistration(fixture.registration) == .updated)
        #expect(
            try await fixture.receipts.load(for: .claudeCode)?.definition
                == fixture.registration.definition)
    }

    @Test("interruption after desired receipt publication restores previous ownership")
    func desiredReceiptPublicationInterrupted() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let transaction = try await prepareTransition(fixture)
        try fixture.write(fixture.registration.definition)
        try await fixture.recovery.recordMutationState(for: transaction)
        try await fixture.receipts.record(desiredReceipt(fixture))

        #expect(
            try await fixture.receipts.recoverConfigurationAndReceipt(
                for: .claudeCode, configurationURL: fixture.configurationURL,
                recovery: fixture.recovery) == .restored)
        #expect(
            try await fixture.receipts.load(for: .claudeCode)?.definition == fixture.oldDefinition)
        #expect(
            try ClaudeUserMCPConfigurationReader(configurationURL: fixture.configurationURL)
                .definition(named: "anchor") == fixture.oldDefinition)
    }

    @Test("interruption during success cleanup retains desired ownership")
    func configurationCompletionInterrupted() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let transaction = try await prepareTransition(fixture)
        try fixture.write(fixture.registration.definition)
        try await fixture.recovery.recordMutationState(for: transaction)
        try await fixture.receipts.record(desiredReceipt(fixture))
        let faultedRecovery = AgentConfigurationRecoveryStore(
            directoryURL: fixture.directory.appendingPathComponent("recovery"),
            persistence: AgentBootstrapFilePersistence { checkpoint in
                if case .publishedFile(let fileURL) = checkpoint,
                    fileURL.lastPathComponent == "manifest.json"
                {
                    throw ClaudeFakeFailure.secret
                }
            })
        await #expect(throws: (any Error).self) { try await faultedRecovery.complete(transaction) }

        #expect(
            try await fixture.receipts.recoverConfigurationAndReceipt(
                for: .claudeCode, configurationURL: fixture.configurationURL,
                recovery: fixture.recovery) == .noTransaction)
        #expect(
            try await fixture.receipts.load(for: .claudeCode)?.definition
                == fixture.registration.definition)
        #expect(
            try ClaudeUserMCPConfigurationReader(configurationURL: fixture.configurationURL)
                .definition(named: "anchor") == fixture.registration.definition)
    }

    @Test(
        "receipt restoration resumes after configuration rollback already completed",
        arguments: [false, true])
    func receiptRestorationInterrupted(afterPublication: Bool) async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let transaction = try await prepareTransition(fixture)
        try fixture.write(fixture.registration.definition)
        try await fixture.recovery.recordMutationState(for: transaction)
        try await fixture.receipts.record(desiredReceipt(fixture))
        try await fixture.receipts.markRollback(transaction)
        #expect(try await fixture.recovery.restore(transaction) == .restored)
        let faultedReceipts = AgentBootstrapReceiptStore(
            directoryURL: fixture.directory.appendingPathComponent("receipts"),
            persistence: AgentBootstrapFilePersistence { checkpoint in
                switch checkpoint {
                case .preparedFile where !afterPublication, .publishedFile where afterPublication:
                    throw ClaudeFakeFailure.secret
                default: break
                }
            })
        await #expect(throws: (any Error).self) {
            try await faultedReceipts.finishTransition(transaction)
        }

        #expect(
            try await fixture.receipts.recoverConfigurationAndReceipt(
                for: .claudeCode, configurationURL: fixture.configurationURL,
                recovery: fixture.recovery) == .noTransaction)
        #expect(
            try await fixture.receipts.load(for: .claudeCode)?.definition == fixture.oldDefinition)
    }

    @Test("startup persists rollback ownership before removing the recovery manifest")
    func startupRecoveryInterrupted() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let transaction = try await prepareTransition(fixture)
        try fixture.write(fixture.registration.definition)
        try await fixture.recovery.recordMutationState(for: transaction)
        try await fixture.receipts.record(desiredReceipt(fixture))
        let faultedRecovery = AgentConfigurationRecoveryStore(
            directoryURL: fixture.directory.appendingPathComponent("recovery"),
            persistence: AgentBootstrapFilePersistence { checkpoint in
                if case .removedFile(let fileURL) = checkpoint,
                    fileURL.lastPathComponent == "manifest.json"
                {
                    throw ClaudeFakeFailure.secret
                }
            })
        await #expect(throws: (any Error).self) {
            try await fixture.receipts.recoverConfigurationAndReceipt(
                for: .claudeCode, configurationURL: fixture.configurationURL,
                recovery: faultedRecovery)
        }
        #expect(
            try await fixture.receipts.recoverConfigurationAndReceipt(
                for: .claudeCode, configurationURL: fixture.configurationURL,
                recovery: fixture.recovery) == .noTransaction)
        #expect(
            try await fixture.receipts.load(for: .claudeCode)?.definition == fixture.oldDefinition)
    }

    @Test("receipt transitions cannot recover a different configuration")
    func transitionIsBoundToConfiguration() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        _ = try await prepareTransition(fixture)
        let bytes = try Data(contentsOf: fixture.configurationURL)
        await #expect(throws: (any Error).self) {
            try await fixture.receipts.recoverConfigurationAndReceipt(
                for: .claudeCode,
                configurationURL: fixture.directory.appendingPathComponent("other.json"),
                recovery: fixture.recovery)
        }
        #expect(try Data(contentsOf: fixture.configurationURL) == bytes)
        #expect(
            try await fixture.receipts.load(for: .claudeCode)?.definition == fixture.oldDefinition)
    }

    private func prepareTransition(
        _ fixture: ClaudeBootstrapFixture
    ) async throws -> AgentConfigurationRecoveryTransaction {
        try await fixture.seedManaged()
        let transaction = try await fixture.recovery.begin(
            client: .claudeCode, configurationURL: fixture.configurationURL)
        try await fixture.receipts.beginTransition(
            transaction, previousReceipt: try await fixture.receipts.load(for: .claudeCode),
            desiredReceipt: desiredReceipt(fixture))
        return transaction
    }

    private func desiredReceipt(_ fixture: ClaudeBootstrapFixture) -> AgentBootstrapReceipt {
        AgentBootstrapReceipt(
            client: .claudeCode, configurationPath: fixture.configurationURL.path,
            definition: fixture.registration.definition)
    }
}
