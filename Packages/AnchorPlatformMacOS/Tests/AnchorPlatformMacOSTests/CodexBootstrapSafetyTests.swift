import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct CodexBootstrapSafetyTests {
    @Test("successful inspection cannot certify a concurrently edited configuration")
    func editDuringVerification() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.runner.inspect(nil)
        await fixture.queueAdd()
        await fixture.runner.append { _ in
            try Data("external secret".utf8).write(to: fixture.configurationURL)
            return try CodexBootstrapFixture.inspection(fixture.registration.definition)
        }
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration) == .recoveryRequired
        )
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("external secret".utf8))
        #expect(try await fixture.receipts.load(for: .codex) == nil)
    }

    @Test("external edit after checkpoint prevents rollback from destroying newer bytes")
    func unsafeRollback() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.runner.inspect(nil)
        await fixture.queueAdd()
        await fixture.runner.append { _ in
            try Data("external secret".utf8).write(to: fixture.configurationURL)
            return CodexBootstrapFixture.output(status: 1, stderr: "failed")
        }
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration) == .recoveryRequired
        )
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("external secret".utf8))
        #expect(
            try await fixture.recovery.recoverIncompleteTransaction(
                for: .codex, configurationURL: fixture.configurationURL)
                == .configurationChangedExternally)
    }

    @Test("interrupted replacement recovers before fresh inspection")
    func interruptedUpdate() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.seedManaged()
        let transaction = try await fixture.recovery.begin(
            client: .codex, configurationURL: fixture.configurationURL)
        try await fixture.receipts.beginTransition(
            transaction,
            previousReceipt: try await fixture.receipts.load(for: .codex),
            desiredReceipt: .init(
                client: .codex, configurationPath: fixture.configurationURL.path,
                definition: fixture.registration.definition))
        try fixture.modifiedBytes.write(to: fixture.configurationURL)
        try await fixture.recovery.recordMutationState(for: transaction)
        try await fixture.receipts.record(
            .init(
                client: .codex, configurationPath: fixture.configurationURL.path,
                definition: fixture.registration.definition))
        await fixture.runner.append { _ in
            #expect(try Data(contentsOf: fixture.configurationURL) == fixture.originalBytes)
            return try CodexBootstrapFixture.inspection(fixture.oldDefinition)
        }
        await fixture.queueAdd(status: 1)
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .failed(.addition))
        #expect(try Data(contentsOf: fixture.configurationURL) == fixture.originalBytes)
        #expect(try await fixture.receipts.load(for: .codex)?.definition == fixture.oldDefinition)
    }

    @Test("external edit during inspection prevents add")
    func editDuringInspection() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        await fixture.runner.append { _ in
            try Data("external secret".utf8).write(to: fixture.configurationURL)
            return try CodexBootstrapFixture.inspection(nil)
        }
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration) == .recoveryRequired
        )
        #expect(await fixture.runner.commands.count == 1)
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("external secret".utf8))
    }

    @Test("external edit while journaling prevents mutation")
    func editBeforeMutation() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        let receipts = AgentBootstrapReceiptStore(
            directoryURL: fixture.directory.appendingPathComponent("race-receipts"),
            persistence: AgentBootstrapFilePersistence { checkpoint in
                if case .publishedFile(let fileURL) = checkpoint,
                    fileURL.deletingLastPathComponent().lastPathComponent == "transitions"
                {
                    try Data("external secret".utf8).write(to: fixture.configurationURL)
                }
            })
        let driver = CodexMCPBootstrapDriver(
            locator: CodexBootstrapLocator(installed: true), runner: fixture.runner,
            configurationURL: fixture.configurationURL, receipts: receipts,
            recovery: fixture.recovery,
            configurationDirectoryURL: fixture.directory)
        try await fixture.runner.inspect(nil)
        #expect(await driver.ensureUserRegistration(fixture.registration) == .recoveryRequired)
        #expect(await fixture.runner.commands.count == 1)
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("external secret".utf8))
    }

    @Test(
        "helper must be an executable regular file",
        arguments: ["missing", "directory", "not-executable"])
    func invalidHelper(kind: String) async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        let executableURL: URL
        switch kind {
        case "directory": executableURL = fixture.directory
        case "not-executable":
            executableURL = fixture.registration.helperExecutableURL
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: executableURL.path)
        default: executableURL = fixture.directory.appendingPathComponent("absent")
        }
        let registration = try #require(
            AgentMCPRegistration(
                serverName: "anchor",
                helperExecutableURL: executableURL, workspaceURL: fixture.directory))
        #expect(await fixture.driver().ensureUserRegistration(registration) == .failed(.discovery))
        #expect(await fixture.runner.commands.isEmpty)
    }

    @Test("an identical run never creates a recovery snapshot")
    func noOpDoesNotBackUp() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        let recovery = AgentConfigurationRecoveryStore(
            directoryURL: fixture.directory.appendingPathComponent("untouched-recovery"),
            persistence: AgentBootstrapFilePersistence { checkpoint in
                switch checkpoint {
                case .createdDirectory, .preparedFile, .publishedFile:
                    throw CodexFakeFailure.secret
                default: break
                }
            })
        try await fixture.runner.inspect(fixture.registration.definition)
        #expect(
            await fixture.driver(recovery: recovery).ensureUserRegistration(fixture.registration)
                == .alreadyConfigured)
    }
}
