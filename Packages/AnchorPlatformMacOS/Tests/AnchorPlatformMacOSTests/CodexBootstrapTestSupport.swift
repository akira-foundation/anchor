import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

enum CodexFakeFailure: Error { case secret }

actor CodexBootstrapRunner: AgentCommandRunning {
    var commands: [AgentCommand] = []
    private var steps: [@Sendable (AgentCommand) throws -> AgentCommandOutput] = []

    func append(_ step: @escaping @Sendable (AgentCommand) throws -> AgentCommandOutput) {
        steps.append(step)
    }

    func inspect(_ definition: AgentMCPDefinition?, extra: [String: String] = [:]) throws {
        let output = try CodexBootstrapFixture.inspection(definition, extra: extra)
        steps.append { _ in output }
    }

    func run(_ command: AgentCommand) async throws -> AgentCommandOutput {
        commands.append(command)
        guard !steps.isEmpty else { throw CodexFakeFailure.secret }
        return try steps.removeFirst()(command)
    }
}

struct CodexBootstrapLocator: AgentExecutableLocating {
    let installed: Bool
    func locate(_ client: AgentClient) async -> URL? {
        installed ? URL(filePath: "/fixture/codex") : nil
    }
}

struct CodexBootstrapFixture: Sendable {
    let directory: URL
    let configurationURL: URL
    let registration: AgentMCPRegistration
    let runner = CodexBootstrapRunner()
    let receipts: AgentBootstrapReceiptStore
    let recovery: AgentConfigurationRecoveryStore
    let oldDefinition = AgentMCPDefinition(
        command: "/old/server", arguments: ["--workspace", "/old"], environment: [:])
    let originalBytes = Data("# preserved comment\nmodel = \"test\"\n".utf8)
    let modifiedBytes = Data(
        "# preserved comment\nmodel = \"test\"\n[mcp_servers.anchor]\ncommand = \"/new/server\"\n"
            .utf8)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Codex é '\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        configurationURL = directory.appendingPathComponent("config.toml")
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

    func driver(
        installed: Bool = true, recovery: AgentConfigurationRecoveryStore? = nil
    ) -> CodexMCPBootstrapDriver {
        CodexMCPBootstrapDriver(
            locator: CodexBootstrapLocator(installed: installed), runner: runner,
            configurationURL: configurationURL, receipts: receipts,
            recovery: recovery ?? self.recovery,
            configurationDirectoryURL: directory)
    }

    func seedManaged(configurationPath: String? = nil) async throws {
        try originalBytes.write(to: configurationURL)
        try await receipts.record(
            .init(
                client: .codex, configurationPath: configurationPath ?? configurationURL.path,
                definition: oldDefinition))
    }

    func queueAdd(status: Int32 = 0, throwsAfterWrite: Bool = false) async {
        await runner.append { _ in
            try modifiedBytes.write(to: configurationURL)
            if throwsAfterWrite { throw CodexFakeFailure.secret }
            return Self.output(status: status)
        }
    }

    static func output(
        status: Int32 = 0, stdout: String = "", stderr: String = ""
    ) -> AgentCommandOutput {
        AgentCommandOutput(
            terminationStatus: status, standardOutput: Data(stdout.utf8),
            standardError: Data(stderr.utf8))
    }

    static func inspection(
        _ definition: AgentMCPDefinition?, extra: [String: String] = [:]
    ) throws -> AgentCommandOutput {
        guard let definition else {
            return output(status: 1, stderr: "Error: No MCP server named 'anchor' found.\n")
        }
        let transport: [String: Any] = [
            "type": "stdio", "command": definition.command, "args": definition.arguments,
            "env": definition.environment, "env_vars": [], "cwd": NSNull(),
        ]
        var document: [String: Any] = [
            "name": "anchor", "enabled": true, "disabled_reason": NSNull(), "transport": transport,
            "enabled_tools": NSNull(), "disabled_tools": NSNull(),
            "startup_timeout_sec": NSNull(), "tool_timeout_sec": NSNull(),
        ]
        for (key, encoded) in extra {
            document[key] = try JSONSerialization.jsonObject(
                with: Data(encoded.utf8), options: [.fragmentsAllowed])
        }
        return AgentCommandOutput(
            terminationStatus: 0,
            standardOutput: try JSONSerialization.data(withJSONObject: document),
            standardError: Data())
    }

    func clean() { try? FileManager.default.removeItem(at: directory) }
}
