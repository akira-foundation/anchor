import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct CodexBootstrapConfigurationContextTests {
    @Test("default context removes inherited CODEX_HOME and uses the default global target")
    func defaultConfigurationContext() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        let configurationURL = fixture.directory.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(
            at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await fixture.runner.inspect(nil)
        await fixture.runner.append { _ in
            try fixture.modifiedBytes.write(to: configurationURL)
            return CodexBootstrapFixture.output()
        }
        try await fixture.runner.inspect(fixture.registration.definition)
        let driver = CodexMCPBootstrapDriver(
            locator: CodexBootstrapLocator(installed: true), runner: fixture.runner,
            configurationURL: configurationURL, receipts: fixture.receipts,
            recovery: fixture.recovery,
            defaultHomeDirectoryURL: fixture.directory)
        #expect(await driver.ensureUserRegistration(fixture.registration) == .configured)
        let commands = await fixture.runner.commands
        #expect(commands.allSatisfy { $0.environment["CODEX_HOME"] == nil })
        #expect(commands.allSatisfy { $0.removedEnvironmentKeys.contains("CODEX_HOME") })
        #expect(commands.allSatisfy { $0.workingDirectoryURL?.path == fixture.directory.path })
        #expect(
            try await fixture.receipts.load(for: .codex)?.configurationPath == configurationURL.path
        )
    }

    @Test("explicit override pins CODEX_HOME for inspection and mutation")
    func explicitConfigurationContext() async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        try await fixture.runner.inspect(nil)
        await fixture.queueAdd()
        try await fixture.runner.inspect(fixture.registration.definition)
        #expect(await fixture.driver().ensureUserRegistration(fixture.registration) == .configured)
        let commands = await fixture.runner.commands
        #expect(commands.allSatisfy { $0.environment == ["CODEX_HOME": fixture.directory.path] })
        #expect(commands.allSatisfy { !$0.removedEnvironmentKeys.contains("CODEX_HOME") })
        #expect(
            commands.allSatisfy {
                !$0.arguments.contains("-c") && !$0.arguments.contains("--config")
            })
    }

    @Test(
        "a mismatched default or override target is rejected before running Codex",
        arguments: [false, true])
    func mismatchedConfiguration(override: Bool) async throws {
        let fixture = try CodexBootstrapFixture()
        defer { fixture.clean() }
        let driver = CodexMCPBootstrapDriver(
            locator: CodexBootstrapLocator(installed: true), runner: fixture.runner,
            configurationURL: fixture.configurationURL, receipts: fixture.receipts,
            recovery: fixture.recovery,
            configurationDirectoryURL: override
                ? fixture.directory.appendingPathComponent("other") : nil,
            defaultHomeDirectoryURL: fixture.directory)
        #expect(await driver.ensureUserRegistration(fixture.registration) == .failed(.inspection))
        #expect(await fixture.runner.commands.isEmpty)
    }
}
