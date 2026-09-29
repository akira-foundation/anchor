import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct CodexMCPBootstrapDriverTests {
    @Test("missing Codex performs no inspection or mutation")
    func notInstalled() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        #expect(
            await fixture.driver(installed: false).ensureUserRegistration(fixture.registration)
                == .notInstalled)
        #expect(await fixture.runner.commands.isEmpty)
    }

    @Test("first add uses global tokens and a second run creates no mutation or backup")
    func firstAddAndSecondNoOp() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.runner.inspect(nil)
        await fixture.queueAdd()
        try await fixture.runner.inspect(fixture.registration.definition)
        let driver = fixture.driver()
        #expect(await driver.ensureUserRegistration(fixture.registration) == .configured)
        try await fixture.runner.inspect(fixture.registration.definition)
        #expect(await driver.ensureUserRegistration(fixture.registration) == .alreadyConfigured)
        #expect(
            await fixture.runner.commands.map(\.arguments) == [
                ["mcp", "get", "anchor", "--json"],
                [
                    "mcp", "add", "anchor", "--", fixture.registration.helperExecutableURL.path,
                    "--workspace", fixture.directory.path,
                ],
                ["mcp", "get", "anchor", "--json"], ["mcp", "get", "anchor", "--json"],
            ])
        #expect(
            try await fixture.receipts.load(for: .codex)?.definition
                == fixture.registration.definition)
        #expect(
            try await fixture.recovery.recoverIncompleteTransaction(
                for: .codex, configurationURL: fixture.configurationURL) == .noTransaction)
        #expect(try Data(contentsOf: fixture.configurationURL) == fixture.modifiedBytes)
    }

    @Test("exact unmanaged configuration is a no-op without recovery or receipt writes")
    func exactNoOp() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try fixture.originalBytes.write(to: fixture.configurationURL)
        try await fixture.runner.inspect(fixture.registration.definition)
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .alreadyConfigured)
        #expect(try Data(contentsOf: fixture.configurationURL) == fixture.originalBytes)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.directory.appendingPathComponent("receipts").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.directory.appendingPathComponent("recovery").path))
    }

    @Test("a stable symlink to the bundled helper is executable")
    func bundledHelperSymlink() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        let helperLinkURL = fixture.directory.appendingPathComponent("Anchor helper link")
        try FileManager.default.createSymbolicLink(
            atPath: helperLinkURL.path,
            withDestinationPath: fixture.registration.helperExecutableURL.lastPathComponent)
        let registration = try #require(
            AgentMCPRegistration(
                serverName: "anchor", helperExecutableURL: helperLinkURL,
                workspaceURL: fixture.directory))
        try await fixture.runner.inspect(registration.definition)

        #expect(await fixture.driver().ensureUserRegistration(registration) == .alreadyConfigured)
    }

    @Test("managed replacement invokes add without remove")
    func managedUpdate() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.seedManaged()
        try await fixture.runner.inspect(fixture.oldDefinition)
        await fixture.queueAdd()
        try await fixture.runner.inspect(fixture.registration.definition)
        #expect(await fixture.driver().ensureUserRegistration(fixture.registration) == .updated)
        #expect(await fixture.runner.commands.map { $0.arguments[1] } == ["get", "add", "get"])
        #expect(
            try await fixture.receipts.load(for: .codex)?.definition
                == fixture.registration.definition)
    }

    @Test(
        "unknown entry or foreign receipt never authorizes replacement", arguments: [false, true])
    func unmanagedPreserved(foreignReceipt: Bool) async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try fixture.originalBytes.write(to: fixture.configurationURL)
        if foreignReceipt { try await fixture.seedManaged(configurationPath: "/other/config.toml") }
        try await fixture.runner.inspect(fixture.oldDefinition)
        #expect(await fixture.driver().ensureUserRegistration(fixture.registration) == .conflict)
        #expect(await fixture.runner.commands.count == 1)
        #expect(try Data(contentsOf: fixture.configurationURL) == fixture.originalBytes)
    }

    @Test("custom server options remain a conflict even with matching ownership receipt")
    func customizedManagedDefinition() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.seedManaged()
        try await fixture.runner.inspect(fixture.oldDefinition, extra: ["enabled": "false"])
        #expect(await fixture.driver().ensureUserRegistration(fixture.registration) == .conflict)
        #expect(await fixture.runner.commands.count == 1)
        #expect(try Data(contentsOf: fixture.configurationURL) == fixture.originalBytes)
    }

    @Test(
        "failed add checkpoints partial writes and restores original absence",
        arguments: [false, true])
    func failedAddRestoresAbsence(throwsAfterWrite: Bool) async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.runner.inspect(nil)
        await fixture.queueAdd(status: 7, throwsAfterWrite: throwsAfterWrite)
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .failed(.addition))
        #expect(!FileManager.default.fileExists(atPath: fixture.configurationURL.path))
        #expect(try await fixture.receipts.load(for: .codex) == nil)
    }

    @Test("failed replacement restores prior bytes and receipt")
    func failedUpdate() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.seedManaged()
        try await fixture.runner.inspect(fixture.oldDefinition)
        await fixture.queueAdd(status: 1)
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .failed(.addition))
        #expect(try Data(contentsOf: fixture.configurationURL) == fixture.originalBytes)
        #expect(try await fixture.receipts.load(for: .codex)?.definition == fixture.oldDefinition)
    }

    @Test("verification mismatch rolls back the successful CLI mutation")
    func verificationMismatch() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.runner.inspect(nil)
        await fixture.queueAdd()
        try await fixture.runner.inspect(fixture.oldDefinition)
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .failed(.verification))
        #expect(!FileManager.default.fileExists(atPath: fixture.configurationURL.path))
    }

    @Test(
        "inspection failure is never mistaken for missing configuration",
        arguments: [
            0, 1, 2,
        ])
    func inspectionFailure(status: Int32) async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        await fixture.runner.append { _ in
            CodexBootstrapFixture.output(
                status: status, stdout: "private invalid JSON", stderr: "private failure")
        }
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .failed(.inspection))
        #expect(await fixture.runner.commands.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.configurationURL.path))
    }

    @Test("not-found text with another exit code is not absence")
    func incorrectNotFoundStatus() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        await fixture.runner.append { _ in
            CodexBootstrapFixture.output(
                status: 2, stderr: "Error: No MCP server named 'anchor' found.\n")
        }
        #expect(
            await fixture.driver().ensureUserRegistration(fixture.registration)
                == .failed(.inspection))
        #expect(await fixture.runner.commands.count == 1)
    }
}
