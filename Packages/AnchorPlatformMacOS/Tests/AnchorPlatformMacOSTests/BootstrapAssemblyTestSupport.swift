import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct BootstrapAssemblyFixture {
    let directory: URL
    let supportURL: URL
    let helperURL: URL
    let workspaceURL: URL
    let claudeURL: URL
    let codexURL: URL
    let environment: [String: String]
    let runner: BootstrapAssemblyRunner

    init(overrides: Bool = false) throws {
        directory =
            FileManager.default.temporaryDirectory.appending(path: "Assembly é \(UUID())")
            .standardizedFileURL
        supportURL = directory.appending(path: "support")
        workspaceURL = directory.appending(path: "project")
        helperURL = directory.appending(path: "Anchor helper")
        let executableDirectory = directory.appending(path: "bin")
        try FileManager.default.createDirectory(
            at: executableDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        for executableURL in [
            helperURL, executableDirectory.appending(path: "claude"),
            executableDirectory.appending(path: "codex"),
        ] {
            try Data().write(to: executableURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
        }
        claudeURL = (overrides ? directory.appending(path: "claude override") : directory)
            .appending(path: ".claude.json")
        codexURL = directory.appending(
            path: overrides ? "codex override/config.toml" : ".codex/config.toml")
        environment = ["HOME": directory.path, "PATH": executableDirectory.path].merging(
            overrides
                ? [
                    "CLAUDE_CONFIG_DIR": claudeURL.deletingLastPathComponent().path,
                    "CODEX_HOME": codexURL.deletingLastPathComponent().path,
                ] : [:]
        ) { _, replacement in replacement }
        runner = BootstrapAssemblyRunner(homeURL: directory)
    }

    func coordinator() -> AgentClientBootstrapCoordinator {
        AgentClientBootstrapAssembly.makeCoordinator(
            supportDirectoryURL: supportURL, homeDirectoryURL: directory,
            environment: environment, knownDirectoryURLs: [], runner: runner)
    }

    func clean() { try? FileManager.default.removeItem(at: directory) }
}

actor BootstrapAssemblyRunner: AgentCommandRunning {
    private let homeURL: URL
    private var codexDefinition: AgentMCPDefinition?
    var commands: [AgentCommand] = []

    init(homeURL: URL) { self.homeURL = homeURL }

    func run(_ command: AgentCommand) async throws -> AgentCommandOutput {
        commands.append(command)
        let isClaude = command.executableURL.lastPathComponent == "claude"
        if command.arguments == ["--version"] {
            return CodexBootstrapFixture.output(
                stdout: isClaude ? "2.1.282 (Claude Code)" : "codex-cli 0.157.0")
        }
        if command.arguments[1] == "get" {
            return isClaude
                ? CodexBootstrapFixture.output()
                : try CodexBootstrapFixture.inspection(codexDefinition)
        }
        #expect(command.arguments[1] == "add")
        let separator = try #require(command.arguments.firstIndex(of: "--"))
        let definition = AgentMCPDefinition(
            command: command.arguments[separator + 1],
            arguments: Array(command.arguments.dropFirst(separator + 2)), environment: [:])
        if isClaude {
            let configurationDirectory =
                command.environment["CLAUDE_CONFIG_DIR"].map { URL(filePath: $0) } ?? homeURL
            try FileManager.default.createDirectory(
                at: configurationDirectory, withIntermediateDirectories: true)
            let bytes = try JSONSerialization.data(withJSONObject: [
                "mcpServers": [
                    "anchor": [
                        "command": definition.command, "args": definition.arguments, "env": [:],
                    ]
                ]
            ])
            try bytes.write(to: configurationDirectory.appending(path: ".claude.json"))
        } else {
            let configurationDirectory =
                command.environment["CODEX_HOME"].map { URL(filePath: $0) }
                ?? homeURL.appending(path: ".codex")
            try FileManager.default.createDirectory(
                at: configurationDirectory, withIntermediateDirectories: true)
            try Data("# fake CLI registration\n".utf8).write(
                to: configurationDirectory.appending(path: "config.toml"))
            codexDefinition = definition
        }
        return CodexBootstrapFixture.output()
    }
}
