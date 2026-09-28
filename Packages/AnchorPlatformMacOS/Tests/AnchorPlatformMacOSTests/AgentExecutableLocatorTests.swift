import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Agent executable locator")
struct AgentExecutableLocatorTests {
    @Test("inherited PATH is searched for a valid Claude Code executable")
    func inheritedPathIsSearched() async throws {
        let rootURL = try makeRoot()
        let pathDirectoryURL = rootURL.appending(path: "path-bin")
        let expectedURL = try makeExecutable(
            in: pathDirectoryURL, named: "claude", versionOutput: "Claude Code 2.1.282")
        let locator = MacOSAgentExecutableLocator(
            environment: ["PATH": pathDirectoryURL.path, "HOME": rootURL.path],
            knownDirectoryURLs: [], runner: FoundationAgentCommandRunner())

        #expect(await locator.locate(.claudeCode) == expectedURL)
    }

    @Test("the user's local bin is searched even when it is absent from PATH")
    func userLocalBinIsSearched() async throws {
        let rootURL = try makeRoot()
        let localBinURL = rootURL.appending(path: ".local/bin")
        let expectedURL = try makeExecutable(
            in: localBinURL, named: "codex", versionOutput: "codex-cli 0.157.0")
        let locator = MacOSAgentExecutableLocator(
            environment: ["PATH": "", "HOME": rootURL.path],
            knownDirectoryURLs: [], runner: FoundationAgentCommandRunner())

        #expect(await locator.locate(.codex) == expectedURL)
    }

    @Test("configured Homebrew and system bin locations are searched")
    func knownMacOSDirectoriesAreSearched() async throws {
        let rootURL = try makeRoot()
        let homebrewURL = rootURL.appending(path: "opt/homebrew/bin")
        let localURL = rootURL.appending(path: "usr/local/bin")
        let systemURL = rootURL.appending(path: "usr/bin")
        let expectedURL = try makeExecutable(
            in: systemURL, named: "codex", versionOutput: "codex-cli 0.157.0")
        let locator = MacOSAgentExecutableLocator(
            environment: ["PATH": "", "HOME": rootURL.path],
            knownDirectoryURLs: [homebrewURL, localURL, systemURL],
            runner: FoundationAgentCommandRunner())

        #expect(await locator.locate(.codex) == expectedURL)
    }

    @Test("a PATH symlink resolves to its executable target")
    func symlinkResolvesToTarget() async throws {
        let rootURL = try makeRoot()
        let targetURL = try makeExecutable(
            in: rootURL.appending(path: "installed"),
            named: "real-claude", versionOutput: "2.1.282")
        let pathDirectoryURL = rootURL.appending(path: "path-bin")
        try FileManager.default.createDirectory(
            at: pathDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: pathDirectoryURL.appending(path: "claude"), withDestinationURL: targetURL)
        let locator = MacOSAgentExecutableLocator(
            environment: ["PATH": pathDirectoryURL.path, "HOME": rootURL.path],
            knownDirectoryURLs: [], runner: FoundationAgentCommandRunner())

        #expect(await locator.locate(.claudeCode) == targetURL)
    }

    @Test("a non-executable same-name file is skipped")
    func nonExecutableFileIsSkipped() async throws {
        let rootURL = try makeRoot()
        let firstURL = rootURL.appending(path: "first")
        let secondURL = rootURL.appending(path: "second")
        let nonExecutableURL = try makeExecutable(
            in: firstURL, named: "codex", versionOutput: "codex-cli 0.157.0")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: nonExecutableURL.path)
        let expectedURL = try makeExecutable(
            in: secondURL, named: "codex", versionOutput: "codex-cli 0.157.0")
        let locator = MacOSAgentExecutableLocator(
            environment: ["PATH": "\(firstURL.path):\(secondURL.path)", "HOME": rootURL.path],
            knownDirectoryURLs: [], runner: FoundationAgentCommandRunner())

        #expect(await locator.locate(.codex) == expectedURL)
    }

    @Test("an earlier same-name executable is skipped when version output identifies another tool")
    func discoveryRequiresExpectedClientIdentity() async throws {
        let rootURL = try makeRoot()
        let firstURL = rootURL.appending(path: "first")
        let secondURL = rootURL.appending(path: "second")
        _ = try makeExecutable(
            in: firstURL, named: "claude", versionOutput: "another-tool 9.0")
        let expectedURL = try makeExecutable(
            in: secondURL, named: "claude", versionOutput: "Claude Code 2.1.282")
        let locator = MacOSAgentExecutableLocator(
            environment: ["PATH": "\(firstURL.path):\(secondURL.path)", "HOME": rootURL.path],
            knownDirectoryURLs: [], runner: FoundationAgentCommandRunner())

        #expect(await locator.locate(.claudeCode) == expectedURL)
    }

    @Test("an unrelated version line mentioning Claude Code is not accepted")
    func incidentalClaudeMentionIsSkipped() async throws {
        let rootURL = try makeRoot()
        let firstURL = rootURL.appending(path: "first")
        let secondURL = rootURL.appending(path: "second")
        _ = try makeExecutable(
            in: firstURL, named: "claude",
            versionOutput: "another-tool 9.0 (compatible with Claude Code)")
        let expectedURL = try makeExecutable(
            in: secondURL, named: "claude", versionOutput: "2.1.282 (Claude Code)")
        let locator = MacOSAgentExecutableLocator(
            environment: ["PATH": "\(firstURL.path):\(secondURL.path)", "HOME": rootURL.path],
            knownDirectoryURLs: [], runner: FoundationAgentCommandRunner())

        #expect(await locator.locate(.claudeCode) == expectedURL)
    }

    @Test("a version command that exits nonzero does not establish installation")
    func failedVersionCommandIsSkipped() async throws {
        let rootURL = try makeRoot()
        let firstURL = rootURL.appending(path: "first")
        let secondURL = rootURL.appending(path: "second")
        _ = try makeExecutable(
            in: firstURL, named: "codex", versionOutput: "codex-cli 0.157.0", exitStatus: 1)
        let expectedURL = try makeExecutable(
            in: secondURL, named: "codex", versionOutput: "codex-cli 0.157.0")
        let locator = MacOSAgentExecutableLocator(
            environment: ["PATH": "\(firstURL.path):\(secondURL.path)", "HOME": rootURL.path],
            knownDirectoryURLs: [], runner: FoundationAgentCommandRunner())

        #expect(await locator.locate(.codex) == expectedURL)
    }

    @Test("discovery gives a slow version probe a short deadline")
    func slowVersionProbeIsSkipped() async throws {
        let rootURL = try makeRoot()
        let firstURL = rootURL.appending(path: "first")
        let secondURL = rootURL.appending(path: "second")
        let slowExecutableURL = try makeExecutable(
            in: firstURL, named: "codex", versionOutput: "codex-cli 0.157.0",
            delaySeconds: 1.5)
        let expectedURL = try makeExecutable(
            in: secondURL, named: "codex", versionOutput: "codex-cli 0.157.0")
        let fixtureStartedAt = ContinuousClock.now
        let fixtureOutput = try await FoundationAgentCommandRunner().run(
            AgentCommand(
                executableURL: slowExecutableURL, arguments: ["--version"],
                environment: ["PATH": ""]))
        #expect(fixtureOutput.terminationStatus == 0)
        #expect(fixtureStartedAt.duration(to: .now) >= .milliseconds(1_200))
        let locator = MacOSAgentExecutableLocator(
            environment: ["PATH": "\(firstURL.path):\(secondURL.path)", "HOME": rootURL.path],
            knownDirectoryURLs: [], runner: FoundationAgentCommandRunner(),
            discoveryMaximumRunDuration: 0.75)

        let locatedURL = await locator.locate(.codex)
        #expect(locatedURL == expectedURL)
    }

    private func makeRoot() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "anchor-agent-locator-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func makeExecutable(
        in directoryURL: URL,
        named name: String,
        versionOutput: String,
        exitStatus: Int = 0,
        delaySeconds: Double = 0
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let executableURL = directoryURL.appending(path: name)
        let delay = delaySeconds > 0 ? "/bin/sleep \(delaySeconds)\n" : ""
        let script = "#!/bin/sh\nset -e\n\(delay)printf '\(versionOutput)\\n'\nexit \(exitStatus)\n"
        try Data(script.utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
        return executableURL
    }
}
