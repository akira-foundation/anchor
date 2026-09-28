import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct ClaudeBootstrapConfigurationContextTests {
    @Test("default configuration must belong to the injected default home")
    func mismatchedDefaultHomeRejected() async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let driver = ClaudeCodeMCPBootstrapDriver(
            locator: ClaudeBootstrapLocator(installed: true), runner: fixture.runner,
            configurationURL: fixture.configurationURL, workingDirectoryURL: fixture.directory,
            receipts: fixture.receipts, recovery: fixture.recovery,
            defaultHomeDirectoryURL: fixture.directory.appendingPathComponent("other-home"))
        #expect(await driver.ensureUserRegistration(fixture.registration) == .failed(.inspection))
        #expect(await fixture.runner.commands.isEmpty)
    }

    @Test(
        "CLI target equals the backed-up target despite an inherited override",
        arguments: [false, true])
    func isolatedCommandUsesBoundTarget(explicitOverride: Bool) async throws {
        let fixture = try ClaudeBootstrapFixture()
        defer { fixture.clean() }
        let unrelatedDirectory = fixture.directory.appendingPathComponent("unrelated-config")
        try FileManager.default.createDirectory(
            at: unrelatedDirectory, withIntermediateDirectories: true)
        let unrelatedConfiguration = unrelatedDirectory.appendingPathComponent(".claude.json")
        let unrelatedBytes = Data("unrelated client state".utf8)
        try unrelatedBytes.write(to: unrelatedConfiguration)
        try fixture.write(fixture.registration.definition)
        let templateURL = fixture.directory.appendingPathComponent("expected-configuration.json")
        try FileManager.default.moveItem(at: fixture.configurationURL, to: templateURL)
        let executableURL = fixture.directory.appendingPathComponent("fake-claude")
        let script = """
            #!/bin/sh
            target="${CLAUDE_CONFIG_DIR:-$ANCHOR_TEST_DEFAULT_HOME}/.claude.json"
            if [ "$2" = "add" ]; then
                /bin/cp "$ANCHOR_TEST_TEMPLATE" "$target"
                exit $?
            fi
            if [ "$2" = "get" ]; then
                test -f "$target"
                exit $?
            fi
            exit 64
            """
        try Data(script.utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
        let runner = FoundationAgentCommandRunner(inheritedEnvironment: [
            "CLAUDE_CONFIG_DIR": unrelatedDirectory.path,
            "ANCHOR_TEST_DEFAULT_HOME": fixture.directory.path,
            "ANCHOR_TEST_TEMPLATE": templateURL.path,
        ])
        let driver = ClaudeCodeMCPBootstrapDriver(
            locator: IsolatedClaudeLocator(executableURL: executableURL), runner: runner,
            configurationURL: fixture.configurationURL, workingDirectoryURL: fixture.directory,
            receipts: fixture.receipts, recovery: fixture.recovery,
            configurationDirectoryURL: explicitOverride ? fixture.directory : nil,
            defaultHomeDirectoryURL: fixture.directory)
        #expect(await driver.ensureUserRegistration(fixture.registration) == .configured)
        #expect(try Data(contentsOf: fixture.configurationURL) == Data(contentsOf: templateURL))
        #expect(try Data(contentsOf: unrelatedConfiguration) == unrelatedBytes)
        #expect(
            try await fixture.receipts.load(for: .claudeCode)?.configurationPath
                == fixture.configurationURL.path)
    }
}

private struct IsolatedClaudeLocator: AgentExecutableLocating {
    let executableURL: URL
    func locate(_ client: AgentClient) async -> URL? { executableURL }
}
