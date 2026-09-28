import AnchorApplication
import Foundation
import Synchronization
import Testing

@testable import AnchorPlatformMacOS

struct AgentMCPRestorationClassificationTests {
    @Test(
        "Claude restoration I/O failures are retryable failures with resumable state",
        arguments: RestorationFault.allCases)
    func claudeRestorationFailure(_ fault: RestorationFault) async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let dependencies = restorationDependencies(
            client: .claudeCode, fault: fault, fixtureDirectory: fixture.directory,
            configurationURL: fixture.configurationURL)
        await fixture.runner.append { _ in
            try fixture.write(fixture.registration.definition)
            return 1
        }
        let driver = ClaudeCodeMCPBootstrapDriver(
            locator: ClaudeBootstrapLocator(installed: true), runner: fixture.runner,
            configurationURL: fixture.configurationURL, workingDirectoryURL: fixture.directory,
            receipts: dependencies.receipts, recovery: dependencies.recovery,
            configurationDirectoryURL: fixture.directory)

        #expect(await driver.ensureUserRegistration(fixture.registration) == .failed(.restoration))
        try await assertResumableRollback(
            client: .claudeCode, fault: fault, fixtureDirectory: fixture.directory,
            configurationURL: fixture.configurationURL)
    }

    @Test(
        "Codex restoration I/O failures are retryable failures with resumable state",
        arguments: RestorationFault.allCases)
    func codexRestorationFailure(_ fault: RestorationFault) async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        let dependencies = restorationDependencies(
            client: .codex, fault: fault, fixtureDirectory: fixture.directory,
            configurationURL: fixture.configurationURL)
        try await fixture.runner.inspect(nil)
        await fixture.queueAdd(status: 1)
        let driver = CodexMCPBootstrapDriver(
            locator: CodexBootstrapLocator(installed: true), runner: fixture.runner,
            configurationURL: fixture.configurationURL, receipts: dependencies.receipts,
            recovery: dependencies.recovery, configurationDirectoryURL: fixture.directory)

        #expect(await driver.ensureUserRegistration(fixture.registration) == .failed(.restoration))
        try await assertResumableRollback(
            client: .codex, fault: fault, fixtureDirectory: fixture.directory,
            configurationURL: fixture.configurationURL)
    }

    @Test(
        "external edits remain recovery-required for both clients", arguments: AgentClient.allCases)
    func externalEditRemainsRecoveryRequired(_ client: AgentClient) async throws {
        let externalBytes = Data("external edit".utf8)
        switch client {
        case .claudeCode:
            let fixture = try ClaudeBootstrapFixture()
            defer { fixture.clean() }
            await fixture.runner.append { _ in
                try fixture.write(fixture.registration.definition)
                return 0
            }
            await fixture.runner.append { _ in
                try externalBytes.write(to: fixture.configurationURL)
                return 1
            }
            #expect(
                await fixture.driver().ensureUserRegistration(fixture.registration)
                    == .recoveryRequired)
            #expect(try Data(contentsOf: fixture.configurationURL) == externalBytes)
        case .codex:
            let fixture = try CodexBootstrapFixture()
            defer { fixture.clean() }
            try await fixture.runner.inspect(nil)
            await fixture.queueAdd()
            await fixture.runner.append { _ in
                try externalBytes.write(to: fixture.configurationURL)
                return CodexBootstrapFixture.output(status: 1)
            }
            #expect(
                await fixture.driver().ensureUserRegistration(fixture.registration)
                    == .recoveryRequired)
            #expect(try Data(contentsOf: fixture.configurationURL) == externalBytes)
        }
    }

    private func restorationDependencies(
        client: AgentClient, fault: RestorationFault, fixtureDirectory: URL,
        configurationURL: URL
    ) -> (
        receipts: AgentBootstrapReceiptStore, recovery: AgentConfigurationRecoveryStore
    ) {
        let faultController = RestorationFaultController(
            client: client, fault: fault, configurationURL: configurationURL)
        return (
            AgentBootstrapReceiptStore(
                directoryURL: fixtureDirectory.appendingPathComponent("receipts"),
                persistence: AgentBootstrapFilePersistence(
                    checkpoint: faultController.inspectReceiptCheckpoint)),
            AgentConfigurationRecoveryStore(
                directoryURL: fixtureDirectory.appendingPathComponent("recovery"),
                persistence: AgentBootstrapFilePersistence(
                    checkpoint: faultController.inspectRecoveryCheckpoint))
        )
    }

    private func assertResumableRollback(
        client: AgentClient, fault: RestorationFault, fixtureDirectory: URL,
        configurationURL: URL
    ) async throws {
        let journalURL = fixtureDirectory.appendingPathComponent(
            "receipts/transitions/\(client.rawValue).json")
        let manifestURL = fixtureDirectory.appendingPathComponent(
            "recovery/\(client.rawValue)/manifest.json")
        #expect(FileManager.default.fileExists(atPath: journalURL.path))
        #expect(FileManager.default.fileExists(atPath: manifestURL.path) == (fault != .finish))

        let receipts = AgentBootstrapReceiptStore(
            directoryURL: fixtureDirectory.appendingPathComponent("receipts"))
        let recovery = AgentConfigurationRecoveryStore(
            directoryURL: fixtureDirectory.appendingPathComponent("recovery"))
        _ = try await receipts.recoverConfigurationAndReceipt(
            for: client, configurationURL: configurationURL, recovery: recovery)
        #expect(!FileManager.default.fileExists(atPath: configurationURL.path))
        #expect(try await receipts.load(for: client) == nil)
        #expect(!FileManager.default.fileExists(atPath: journalURL.path))
        #expect(!FileManager.default.fileExists(atPath: manifestURL.path))
    }
}

enum RestorationFault: CaseIterable, Sendable {
    case mark
    case restore
    case finish
}

private final class RestorationFaultController: Sendable {
    private struct State: Sendable {
        var transitionPreparations = 0
        var didThrow = false
    }

    private let client: AgentClient
    private let fault: RestorationFault
    private let configurationURL: URL
    private let state = Mutex(State())

    init(client: AgentClient, fault: RestorationFault, configurationURL: URL) {
        self.client = client
        self.fault = fault
        self.configurationURL = configurationURL
    }

    func inspectReceiptCheckpoint(_ checkpoint: AgentBootstrapFilePersistence.Checkpoint) throws {
        try state.withLock { state in
            switch checkpoint {
            case .preparedFile(let fileURL)
            where fault == .mark
                && fileURL.deletingLastPathComponent().lastPathComponent == "transitions":
                state.transitionPreparations += 1
                if state.transitionPreparations == 2 { try throwOnce(&state) }
            case .removingFile(let fileURL)
            where fault == .finish
                && fileURL.lastPathComponent == "\(client.rawValue).json"
                && fileURL.deletingLastPathComponent().lastPathComponent == "transitions":
                try throwOnce(&state)
            default: break
            }
        }
    }

    func inspectRecoveryCheckpoint(_ checkpoint: AgentBootstrapFilePersistence.Checkpoint) throws {
        try state.withLock { state in
            guard fault == .restore, case .removingFile(let fileURL) = checkpoint,
                fileURL.path == configurationURL.path
            else { return }
            try throwOnce(&state)
        }
    }

    private func throwOnce(_ state: inout State) throws {
        guard !state.didThrow else { return }
        state.didThrow = true
        throw RestorationFaultFailure.injected
    }
}

private enum RestorationFaultFailure: Error {
    case injected
}
