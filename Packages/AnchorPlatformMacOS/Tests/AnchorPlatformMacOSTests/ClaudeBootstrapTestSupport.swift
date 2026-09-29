import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

enum ClaudeFakeFailure: Error { case secret }

actor ClaudeBootstrapRunner: AgentCommandRunning {
    var commands: [AgentCommand] = []
    private var steps: [@Sendable (AgentCommand) throws -> Int32] = []
    func append(_ step: @escaping @Sendable (AgentCommand) throws -> Int32) { steps.append(step) }
    func run(_ command: AgentCommand) async throws -> AgentCommandOutput {
        commands.append(command)
        let status = try steps.isEmpty ? 0 : steps.removeFirst()(command)
        return AgentCommandOutput(
            terminationStatus: status, standardOutput: Data("secret output".utf8),
            standardError: Data("secret error".utf8))
    }
}

struct ClaudeBootstrapLocator: AgentExecutableLocating {
    let installed: Bool
    func locate(_ client: AgentClient) async -> URL? {
        installed ? URL(filePath: "/fixture/claude") : nil
    }
}

struct ClaudeBootstrapFixture: Sendable {
    let directory: URL
    let configurationURL: URL
    let registration: AgentMCPRegistration
    let runner = ClaudeBootstrapRunner()
    let receipts: AgentBootstrapReceiptStore
    let recovery: AgentConfigurationRecoveryStore
    let oldDefinition = AgentMCPDefinition(
        command: "/old/server", arguments: ["--workspace", "/old"], environment: [:])
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Claude é '\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        configurationURL = directory.appendingPathComponent(".claude.json")
        let executableURL = directory.appendingPathComponent("Anchor é helper")
        try Data().write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
        registration = try #require(
            AgentMCPRegistration(
                serverName: "anchor", helperExecutableURL: executableURL, workspaceURL: directory))
        receipts = AgentBootstrapReceiptStore(
            directoryURL: directory.appendingPathComponent("receipts"))
        recovery = AgentConfigurationRecoveryStore(
            directoryURL: directory.appendingPathComponent("recovery"))
    }
    func driver(installed: Bool = true) -> ClaudeCodeMCPBootstrapDriver {
        ClaudeCodeMCPBootstrapDriver(
            locator: ClaudeBootstrapLocator(installed: installed), runner: runner,
            configurationURL: configurationURL, workingDirectoryURL: directory, receipts: receipts,
            recovery: recovery, configurationDirectoryURL: directory)
    }
    func write(_ definition: AgentMCPDefinition?) throws {
        let servers: [String: Any] =
            definition.map {
                [
                    "anchor": [
                        "type": "stdio", "command": $0.command, "args": $0.arguments,
                        "env": $0.environment,
                    ]
                ]
            } ?? [:]
        try JSONSerialization.data(
            withJSONObject: ["mcpServers": servers, "unrelated": "retained"], options: [.sortedKeys]
        ).write(to: configurationURL)
    }
    func seedManaged() async throws {
        try write(oldDefinition)
        try await receipts.record(
            .init(
                client: .claudeCode, configurationPath: configurationURL.path,
                definition: oldDefinition))
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
}
