import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct ClaudeCodeMCPBootstrapDriverTests {
    @Test("missing CLI performs no mutation")
    func notInstalled() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        #expect(
            await fixture.driver(installed: false).ensureUserRegistration(fixture.registration)
                == .notInstalled)
        #expect(await fixture.runner.commands.isEmpty)
    }

    @Test("first add is global with separate path tokens and an official status check")
    func firstAdd() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        await fixture.runner.append { _ in
            try fixture.write(fixture.registration.definition)
            return 0
        }
        #expect(await fixture.driver().ensureUserRegistration(fixture.registration) == .configured)
        let commands = await fixture.runner.commands
        #expect(
            commands.map(\.arguments) == [
                [
                    "mcp", "add", "--scope", "user", "--transport", "stdio", "anchor", "--",
                    fixture.registration.helperExecutableURL.path, "--workspace",
                    fixture.directory.path,
                ],
                ["mcp", "get", "anchor"],
            ])
        #expect(
            commands.allSatisfy { $0.environment["CLAUDE_CONFIG_DIR"] == fixture.directory.path })
        #expect(commands.allSatisfy { $0.workingDirectoryURL?.path == fixture.directory.path })
        #expect(
            try await fixture.receipts.load(for: .claudeCode)?.definition
                == fixture.registration.definition)
        #expect(
            try await fixture.recovery.recoverIncompleteTransaction(
                for: .claudeCode, configurationURL: fixture.configurationURL) == .noTransaction)
    }

    @Test("exact registration is a byte-preserving no-op without receipt or recovery writes")
    func exactNoOp() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        try fixture.write(fixture.registration.definition)
        let bytes = try Data(contentsOf: fixture.configurationURL)
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .alreadyConfigured)
        #expect(await fixture.runner.commands.isEmpty)
        #expect(try Data(contentsOf: fixture.configurationURL) == bytes)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.directory.appendingPathComponent("receipts").path))
    }

    @Test("a stable symlink to the bundled helper is executable")
    func bundledHelperSymlink() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let helperLinkURL = fixture.directory.appendingPathComponent("Anchor helper link")
        try FileManager.default.createSymbolicLink(
            atPath: helperLinkURL.path,
            withDestinationPath: fixture.registration.helperExecutableURL.lastPathComponent)
        let registration = try #require(
            AgentMCPRegistration(
                serverName: "anchor", helperExecutableURL: helperLinkURL,
                workspaceURL: fixture.directory))
        try fixture.write(registration.definition)

        #expect(await fixture.driver().ensureUserRegistration(registration) == .alreadyConfigured)
    }

    @Test("receipt-owned update removes only user scope then adds and verifies")
    func managedUpdate() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.seedManaged()
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
            await fixture.runner.commands.first?.arguments == [
                "mcp", "remove", "--scope", "user", "anchor",
            ])
        #expect(
            try await fixture.receipts.load(for: .claudeCode)?.definition
                == fixture.registration.definition)
    }

    @Test(
        "unknown definitions and foreign receipts never authorize replacement",
        arguments: [false, true])
    func unmanagedPreserved(foreignReceipt: Bool) async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        try fixture.write(fixture.oldDefinition)
        if foreignReceipt {
            try await fixture.receipts.record(
                .init(
                    client: .claudeCode, configurationPath: "/other/.claude.json",
                    definition: fixture.oldDefinition))
        }
        let bytes = try Data(contentsOf: fixture.configurationURL)
        #expect(await fixture.driver().ensureUserRegistration(fixture.registration) == .conflict)
        #expect(await fixture.runner.commands.isEmpty)
        #expect(try Data(contentsOf: fixture.configurationURL) == bytes)
    }

    @Test(
        "a shadowing local or project anchor definition is a non-destructive conflict",
        arguments: [true, false])
    func shadowingClaudeScopeIsPreserved(local: Bool) async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        if local {
            try JSONSerialization.data(withJSONObject: [
                "projects": [
                    fixture.directory.path: ["mcpServers": ["anchor": ["command": "/local"]]]
                ]
            ])
            .write(to: fixture.configurationURL)
        } else {
            try Data(#"{"mcpServers":{"anchor":{"command":"/project"}}}"#.utf8)
                .write(to: fixture.directory.appendingPathComponent(".mcp.json"))
        }
        #expect(await fixture.driver().ensureUserRegistration(fixture.registration) == .conflict)
        #expect(await fixture.runner.commands.isEmpty)
    }

    @Test(
        "failed add restores original absence even after a partial write", arguments: [false, true])
    func failedAddRestoresAbsence(throwsAfterWrite: Bool) async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        await fixture.runner.append { _ in
            try fixture.write(fixture.registration.definition)
            if throwsAfterWrite { throw ClaudeFakeFailure.secret }
            return 1
        }
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .failed(.addition))
        #expect(!FileManager.default.fileExists(atPath: fixture.configurationURL.path))
    }

    @Test("failed remove restores exact prior bytes and retains prior ownership")
    func failedRemoveRestoresOriginal() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.seedManaged()
        let bytes = try Data(contentsOf: fixture.configurationURL)
        await fixture.runner.append { _ in
            try fixture.write(nil)
            return 1
        }
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration) == .failed(.removal)
        )
        #expect(try Data(contentsOf: fixture.configurationURL) == bytes)
        #expect(
            try await fixture.receipts.load(for: .claudeCode)?.definition == fixture.oldDefinition)
        #expect(await fixture.runner.commands.count == 1)
    }

    @Test("semantic mismatch rolls back instead of claiming success")
    func verificationMismatch() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        await fixture.runner.append { _ in
            try fixture.write(fixture.oldDefinition)
            return 0
        }
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .failed(.verification))
        #expect(!FileManager.default.fileExists(atPath: fixture.configurationURL.path))
    }

    @Test("official inspection failure restores original bytes and redacts captured secrets")
    func failedInspection() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        try fixture.write(nil)
        let bytes = try Data(contentsOf: fixture.configurationURL)
        await fixture.runner.append { _ in
            try fixture.write(fixture.registration.definition)
            return 0
        }
        await fixture.runner.append { _ in 42 }
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .failed(.verification))
        #expect(try Data(contentsOf: fixture.configurationURL) == bytes)
        #expect(try await fixture.receipts.load(for: .claudeCode) == nil)
    }

    @Test("external edit after mutation checkpoint is preserved with recovery required")
    func unsafeRollback() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        await fixture.runner.append { _ in
            try fixture.write(fixture.registration.definition)
            return 0
        }
        await fixture.runner.append { _ in
            try Data("external secret".utf8).write(to: fixture.configurationURL)
            return 1
        }
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration) == .recoveryRequired
        )
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("external secret".utf8))
        #expect(
            try await fixture.recovery.recoverIncompleteTransaction(
                for: .claudeCode, configurationURL: fixture.configurationURL)
                == .configurationChangedExternally)
    }

    @Test("an interrupted remove is recovered before inspection or add")
    func interruptedClaudeUpdateRecoversFirst() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        try fixture.write(fixture.registration.definition)
        let transaction = try await fixture.recovery.begin(
            client: .claudeCode, configurationURL: fixture.configurationURL)
        try fixture.write(nil)
        try await fixture.recovery.recordMutationState(for: transaction)
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .alreadyConfigured)
        #expect(await fixture.runner.commands.isEmpty)
        #expect(
            try ClaudeUserMCPConfigurationReader(configurationURL: fixture.configurationURL)
                .definition(named: "anchor") == fixture.registration.definition)
    }

    @Test("malformed configuration fails before commands")
    func invalidConfiguration() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        try Data("secret malformed".utf8).write(to: fixture.configurationURL)
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .failed(.inspection))
        #expect(await fixture.runner.commands.isEmpty)
    }

    @Test("an external edit during backup is preserved before any CLI mutation")
    func externalEditDuringBackup() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let recoveryDirectory = fixture.directory.appendingPathComponent("recovery-race")
        let recovery = AgentConfigurationRecoveryStore(
            directoryURL: recoveryDirectory,
            persistence: AgentBootstrapFilePersistence { checkpoint in
                if case .createdDirectory(let directory) = checkpoint,
                    directory.path == recoveryDirectory.path
                {
                    try Data("external secret".utf8).write(to: fixture.configurationURL)
                }
            })
        let driver = ClaudeCodeMCPBootstrapDriver(
            locator: ClaudeBootstrapLocator(installed: true), runner: fixture.runner,
            configurationURL: fixture.configurationURL, workingDirectoryURL: fixture.directory,
            receipts: fixture.receipts, recovery: recovery,
            configurationDirectoryURL: fixture.directory)
        #expect(await driver.ensureUserRegistration(fixture.registration) == .recoveryRequired)
        #expect(await fixture.runner.commands.isEmpty)
        #expect(try Data(contentsOf: fixture.configurationURL) == Data("external secret".utf8))
    }
}
