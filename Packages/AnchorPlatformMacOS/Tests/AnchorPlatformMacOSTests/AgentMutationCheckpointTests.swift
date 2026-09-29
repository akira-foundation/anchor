import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct AgentMutationCheckpointTests {
    @Test("conditional checkpoint rejects an external edit without authorizing its rollback")
    func conditionalCheckpointPreservesExternalEdit() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try fixture.originalBytes.write(to: fixture.configurationURL)
        let transaction = try await fixture.recovery.begin(
            client: .codex, configurationURL: fixture.configurationURL)
        let manifestURL = fixture.directory.appendingPathComponent("recovery/codex/manifest.json")
        let originalManifest = try Data(contentsOf: manifestURL)
        try fixture.modifiedBytes.write(to: fixture.configurationURL)
        let capturedFingerprint = AgentConfigurationFingerprint(bytes: fixture.modifiedBytes)
        let externalBytes = Data("external edit".utf8)
        try externalBytes.write(to: fixture.configurationURL)
        await #expect(throws: AgentConfigurationCheckpointFailure.configurationChangedExternally) {
            try await fixture.recovery.recordMutationState(
                for: transaction, expectedFingerprint: capturedFingerprint)
        }
        #expect(try Data(contentsOf: manifestURL) == originalManifest)
        let restarted = AgentConfigurationRecoveryStore(
            directoryURL: fixture.directory.appendingPathComponent("recovery"))
        #expect(
            try await restarted.recoverIncompleteTransaction(
                for: .codex,
                configurationURL: fixture.configurationURL) == .configurationChangedExternally)
        #expect(try Data(contentsOf: fixture.configurationURL) == externalBytes)
    }

    @Test("conditional checkpoint accepts the captured state and permits exact rollback")
    func conditionalCheckpointAcceptsCapturedMutation() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try fixture.originalBytes.write(to: fixture.configurationURL)
        let transaction = try await fixture.recovery.begin(
            client: .codex, configurationURL: fixture.configurationURL)
        try fixture.modifiedBytes.write(to: fixture.configurationURL)
        try await fixture.recovery.recordMutationState(
            for: transaction,
            expectedFingerprint: AgentConfigurationFingerprint(bytes: fixture.modifiedBytes))
        #expect(try await fixture.recovery.restore(transaction) == .restored)
        #expect(try Data(contentsOf: fixture.configurationURL) == fixture.originalBytes)
    }

    @Test(
        "Codex never adopts an edit between capture and checkpoint",
        arguments: ["nonzero", "throw", "verification"])
    func codexCaptureCheckpointRace(failure: String) async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        let externalBytes = Data("external edit".utf8)
        let recoveryDirectory = fixture.directory.appendingPathComponent("race-recovery")
        let recovery = AgentConfigurationRecoveryStore(
            directoryURL: recoveryDirectory,
            persistence: AgentBootstrapFilePersistence { checkpoint in
                if case .validatingMutationState(let configurationURL) = checkpoint {
                    try externalBytes.write(to: configurationURL)
                }
            })
        try await fixture.runner.inspect(nil)
        await fixture.queueAdd(
            status: failure == "verification" ? 0 : 1, throwsAfterWrite: failure == "throw")
        try await fixture.runner.inspect(fixture.oldDefinition)
        #expect(
            await fixture.driver(recovery: recovery).ensureUserRegistration(fixture.registration)
                == .recoveryRequired)
        #expect(await fixture.runner.commands.count == 2)
        #expect(try Data(contentsOf: fixture.configurationURL) == externalBytes)
        let restarted = AgentConfigurationRecoveryStore(directoryURL: recoveryDirectory)
        #expect(
            await fixture.driver(recovery: restarted).ensureUserRegistration(fixture.registration)
                == .recoveryRequired)
        #expect(await fixture.runner.commands.count == 2)
        #expect(try Data(contentsOf: fixture.configurationURL) == externalBytes)
        #expect(
            FileManager.default.fileExists(
                atPath: recoveryDirectory.appendingPathComponent("codex/manifest.json").path))
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.directory.appendingPathComponent("receipts/transitions/codex.json")
                    .path))
    }

    @Test(
        "Claude never adopts an edit between capture and checkpoint",
        arguments: ["nonzero", "throw", "verification"])
    func claudeCaptureCheckpointRace(failure: String) async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let externalBytes = Data(#"{"mcpServers":{"external":{"command":"/custom"}}}"#.utf8)
        let recoveryDirectory = fixture.directory.appendingPathComponent("race-recovery")
        let recovery = AgentConfigurationRecoveryStore(
            directoryURL: recoveryDirectory,
            persistence: AgentBootstrapFilePersistence { checkpoint in
                if case .validatingMutationState(let configurationURL) = checkpoint {
                    try externalBytes.write(to: configurationURL)
                }
            })
        await fixture.runner.append { _ in
            try fixture.write(fixture.registration.definition)
            if failure == "throw" { throw ClaudeFakeFailure.secret }
            return failure == "verification" ? 0 : 1
        }
        let driver = ClaudeCodeMCPBootstrapDriver(
            locator: ClaudeBootstrapLocator(installed: true), runner: fixture.runner,
            configurationURL: fixture.configurationURL, workingDirectoryURL: fixture.directory,
            receipts: fixture.receipts, recovery: recovery,
            configurationDirectoryURL: fixture.directory)
        #expect(await driver.ensureUserRegistration(fixture.registration) == .recoveryRequired)
        #expect(await fixture.runner.commands.count == 1)
        #expect(try Data(contentsOf: fixture.configurationURL) == externalBytes)
        let restarted = AgentConfigurationRecoveryStore(directoryURL: recoveryDirectory)
        #expect(
            try await fixture.receipts.recoverConfigurationAndReceipt(
                for: .claudeCode,
                configurationURL: fixture.configurationURL, recovery: restarted)
                == .configurationChangedExternally)
        #expect(try Data(contentsOf: fixture.configurationURL) == externalBytes)
        #expect(
            FileManager.default.fileExists(
                atPath: recoveryDirectory.appendingPathComponent("claudeCode/manifest.json").path))
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.directory.appendingPathComponent(
                    "receipts/transitions/claudeCode.json"
                ).path))
    }

    @Test(
        "publication race cannot replace the captured checkpoint with external bytes",
        arguments: [false, true])
    func editDuringCheckpointPublication(verificationFailure: Bool) async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        let externalBytes = Data("external edit".utf8)
        let recoveryDirectory = fixture.directory.appendingPathComponent("race-recovery")
        let recovery = AgentConfigurationRecoveryStore(
            directoryURL: recoveryDirectory,
            persistence: AgentBootstrapFilePersistence { checkpoint in
                if case .preparedFile = checkpoint,
                    (try? Data(contentsOf: fixture.configurationURL)) == fixture.modifiedBytes
                {
                    try externalBytes.write(to: fixture.configurationURL)
                }
            })
        try await fixture.runner.inspect(nil)
        await fixture.queueAdd(status: verificationFailure ? 0 : 1)
        try await fixture.runner.inspect(fixture.oldDefinition)
        #expect(
            await fixture.driver(recovery: recovery).ensureUserRegistration(fixture.registration)
                == .recoveryRequired)
        #expect(try Data(contentsOf: fixture.configurationURL) == externalBytes)
        let restarted = AgentConfigurationRecoveryStore(directoryURL: recoveryDirectory)
        #expect(
            try await restarted.recoverIncompleteTransaction(
                for: .codex,
                configurationURL: fixture.configurationURL) == .configurationChangedExternally)
        #expect(try Data(contentsOf: fixture.configurationURL) == externalBytes)
    }
}
