import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct ClaudeBootstrapSafetyTests {
    @Test("external edits after managed removal prevent the add command")
    func externalEditBetweenCommands() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.seedManaged()
        let externalBytes = Data(#"{"mcpServers":{"anchor":{"command":"/external"}}}"#.utf8)
        let recovery = AgentConfigurationRecoveryStore(
            directoryURL: fixture.directory.appendingPathComponent("race-recovery"),
            persistence: AgentBootstrapFilePersistence { checkpoint in
                guard case .publishedFile(let fileURL) = checkpoint,
                    fileURL.lastPathComponent == "manifest.json",
                    try ClaudeUserMCPConfigurationReader(configurationURL: fixture.configurationURL)
                        .definition(named: "anchor") == nil
                else { return }
                try externalBytes.write(to: fixture.configurationURL)
            })
        await fixture.runner.append { _ in
            try fixture.write(nil)
            return 0
        }
        await fixture.runner.append { _ in 1 }
        let driver = ClaudeCodeMCPBootstrapDriver(
            locator: ClaudeBootstrapLocator(installed: true), runner: fixture.runner,
            configurationURL: fixture.configurationURL, workingDirectoryURL: fixture.directory,
            receipts: fixture.receipts, recovery: recovery,
            configurationDirectoryURL: fixture.directory)
        #expect(await driver.ensureUserRegistration(fixture.registration) == .recoveryRequired)
        #expect(
            await fixture.runner.commands.map(\.arguments) == [
                ["mcp", "remove", "--scope", "user", "anchor"]
            ])
        #expect(try Data(contentsOf: fixture.configurationURL) == externalBytes)
    }

    @Test("default Claude configuration context does not relocate settings or history")
    func defaultContextOmitsOverride() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        await fixture.runner.append { _ in
            try fixture.write(fixture.registration.definition)
            return 0
        }
        let driver = ClaudeCodeMCPBootstrapDriver(
            locator: ClaudeBootstrapLocator(installed: true), runner: fixture.runner,
            configurationURL: fixture.configurationURL, workingDirectoryURL: fixture.directory,
            receipts: fixture.receipts, recovery: fixture.recovery,
            defaultHomeDirectoryURL: fixture.directory)
        #expect(await driver.ensureUserRegistration(fixture.registration) == .configured)
        #expect(
            await fixture.runner.commands.allSatisfy { $0.environment["CLAUDE_CONFIG_DIR"] == nil })
    }

    @Test("explicit configuration override must match the backed-up JSON target")
    func mismatchedOverrideRejected() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let driver = ClaudeCodeMCPBootstrapDriver(
            locator: ClaudeBootstrapLocator(installed: true), runner: fixture.runner,
            configurationURL: fixture.configurationURL, workingDirectoryURL: fixture.directory,
            receipts: fixture.receipts, recovery: fixture.recovery,
            configurationDirectoryURL: fixture.directory.appendingPathComponent("other"))
        #expect(await driver.ensureUserRegistration(fixture.registration) == .failed(.inspection))
        #expect(await fixture.runner.commands.isEmpty)
    }

    @Test("an executable directory is not an MCP helper")
    func executableDirectoryRejected() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let registration = try #require(
            AgentMCPRegistration(
                serverName: "anchor", helperExecutableURL: fixture.directory,
                workspaceURL: fixture.directory))
        #expect(await fixture.driver().ensureUserRegistration(registration) == .failed(.discovery))
        #expect(await fixture.runner.commands.isEmpty)
    }
}
