import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct AgentClientBootstrapAssemblyTests {
    @Test func validHelperRecoversInterruptedClientsBeforeDiscoveringTheirRemoval() async throws {
        let fixture = try BootstrapAssemblyFixture()
        defer { fixture.clean() }
        let bootstrapURL = fixture.supportURL.appending(path: "agent-bootstrap")
        let recoveryURL = bootstrapURL.appending(path: "recovery")
        let receiptsURL = bootstrapURL.appending(path: "receipts")
        let recovery = AgentConfigurationRecoveryStore(directoryURL: recoveryURL)
        let receipts = AgentBootstrapReceiptStore(directoryURL: receiptsURL)
        let originalBytes = Data("original configuration".utf8)
        for (client, configurationURL, executableName) in [
            (AgentClient.claudeCode, fixture.claudeURL, "claude"),
            (.codex, fixture.codexURL, "codex"),
        ] {
            try FileManager.default.createDirectory(
                at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try originalBytes.write(to: configurationURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o640], ofItemAtPath: configurationURL.path)
            let transaction = try await recovery.begin(
                client: client, configurationURL: configurationURL)
            let receipt = AgentBootstrapReceipt(
                client: client, configurationPath: configurationURL.path,
                definition: .init(command: "/fixture/server", arguments: [], environment: [:]))
            try await receipts.beginTransition(
                transaction, previousReceipt: nil, desiredReceipt: receipt)
            try Data("interrupted replacement".utf8).write(to: configurationURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
            try await recovery.recordMutationState(for: transaction)
            try await receipts.record(receipt)
            try FileManager.default.removeItem(
                at: fixture.directory.appending(path: "bin/\(executableName)"))
        }

        let report = await fixture.coordinator().reconcile(
            helperExecutableURL: fixture.helperURL, workspaceURL: fixture.workspaceURL)

        #expect(report?.entries.map(\.outcome) == [.notInstalled, .notInstalled])
        #expect(await fixture.runner.commands.isEmpty)
        for (client, configurationURL) in [
            (AgentClient.claudeCode, fixture.claudeURL), (.codex, fixture.codexURL),
        ] {
            #expect(try Data(contentsOf: configurationURL) == originalBytes)
            #expect(
                try FileManager.default.attributesOfItem(
                    atPath: configurationURL.path)[.posixPermissions] as? Int == 0o640)
            #expect(try await receipts.load(for: client) == nil)
            #expect(
                try FileManager.default.contentsOfDirectory(
                    atPath: recoveryURL.appending(path: client.rawValue).path
                ).isEmpty)
            #expect(
                !FileManager.default.fileExists(
                    atPath: receiptsURL.appending(path: "transitions/\(client.rawValue).json").path)
            )
        }
    }

    @Test(arguments: [false, true]) func configuresIsolatedTargetsAndPersistsReceipts(
        overrides: Bool
    ) async throws {
        let fixture = try BootstrapAssemblyFixture(overrides: overrides)
        defer { fixture.clean() }
        let coordinator = fixture.coordinator()
        let report = await coordinator.reconcile(
            helperExecutableURL: fixture.helperURL, workspaceURL: fixture.workspaceURL)
        #expect(report?.entries.map(\.client) == [.claudeCode, .codex])
        #expect(report?.entries.map(\.outcome) == [.configured, .configured])
        let receipts = AgentBootstrapReceiptStore(
            directoryURL: fixture.supportURL.appending(path: "agent-bootstrap/receipts"))
        #expect(
            try await receipts.load(for: .claudeCode)?.configurationPath == fixture.claudeURL.path)
        #expect(try await receipts.load(for: .codex)?.configurationPath == fixture.codexURL.path)
        let recoveryURL = fixture.supportURL.appending(path: "agent-bootstrap/recovery")
        for client in ["claudeCode", "codex"] {
            #expect(
                try FileManager.default.contentsOfDirectory(
                    atPath: recoveryURL.appending(path: client).path
                ).isEmpty)
        }
        let commands = await fixture.runner.commands.filter { $0.arguments != ["--version"] }
        #expect(
            commands.allSatisfy {
                $0.workingDirectoryURL?.path.hasPrefix(fixture.directory.path) == true
            })
        for command in commands {
            let isClaude = command.executableURL.lastPathComponent == "claude"
            let key = isClaude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"
            if overrides {
                #expect(
                    command.environment[key]
                        == (isClaude ? fixture.claudeURL : fixture.codexURL)
                        .deletingLastPathComponent().path)
            } else {
                #expect(command.environment[key] == nil)
                #expect(command.removedEnvironmentKeys.contains(key))
            }
        }
        let repeatReport = await coordinator.reconcile(
            helperExecutableURL: fixture.helperURL, workspaceURL: fixture.workspaceURL)
        #expect(repeatReport?.entries.map(\.outcome) == [.alreadyConfigured, .alreadyConfigured])
        #expect(await fixture.runner.commands.filter { $0.arguments.contains("add") }.count == 2)
    }

    @Test func missingHelperFailsInstalledClientsBeforeConfigurationCommands() async throws {
        let fixture = try BootstrapAssemblyFixture()
        defer { fixture.clean() }
        let report = await fixture.coordinator().reconcile(
            helperExecutableURL: fixture.directory.appending(path: "missing"),
            workspaceURL: fixture.workspaceURL)
        #expect(report?.entries.map(\.outcome) == [.failed(.discovery), .failed(.discovery)])
        #expect(await fixture.runner.commands.map(\.arguments) == [["--version"], ["--version"]])
        #expect(!FileManager.default.fileExists(atPath: fixture.claudeURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.codexURL.path))
    }

    @Test func retryChecksShadowingInNewWorkspace() async throws {
        let fixture = try BootstrapAssemblyFixture()
        defer { fixture.clean() }
        let coordinator = fixture.coordinator()
        _ = await coordinator.reconcile(
            helperExecutableURL: fixture.helperURL, workspaceURL: fixture.workspaceURL)
        let otherWorkspace = fixture.directory.appending(path: "other project")
        try FileManager.default.createDirectory(
            at: otherWorkspace, withIntermediateDirectories: true)
        try Data(#"{"mcpServers":{"anchor":{"command":"/custom/server","args":[],"env":{}}}}"#.utf8)
            .write(to: otherWorkspace.appending(path: ".mcp.json"))
        let report = await coordinator.reconcile(
            helperExecutableURL: fixture.helperURL, workspaceURL: otherWorkspace)
        #expect(report?.entries.map(\.outcome) == [.conflict, .updated])
    }

    @Test func missingHelperPreservesPendingRecoveryBytesAndPermissions() async throws {
        let fixture = try BootstrapAssemblyFixture()
        defer { fixture.clean() }
        let bootstrapURL = fixture.supportURL.appending(path: "agent-bootstrap")
        let recoveryURL = bootstrapURL.appending(path: "recovery")
        let receiptsURL = bootstrapURL.appending(path: "receipts")
        let recovery = AgentConfigurationRecoveryStore(directoryURL: recoveryURL)
        let receipts = AgentBootstrapReceiptStore(directoryURL: receiptsURL)
        var protectedFiles: [URL] = []
        for (client, configurationURL) in [
            (AgentClient.claudeCode, fixture.claudeURL), (.codex, fixture.codexURL),
        ] {
            try FileManager.default.createDirectory(
                at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("original".utf8).write(to: configurationURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o640], ofItemAtPath: configurationURL.path)
            let transaction = try await recovery.begin(
                client: client, configurationURL: configurationURL)
            let receipt = AgentBootstrapReceipt(
                client: client, configurationPath: configurationURL.path,
                definition: .init(command: "/fixture/server", arguments: [], environment: [:]))
            try await receipts.beginTransition(
                transaction, previousReceipt: nil, desiredReceipt: receipt)
            try Data("interrupted mutation".utf8).write(to: configurationURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
            try await recovery.recordMutationState(for: transaction)
            try await receipts.record(receipt)
            protectedFiles += [
                configurationURL,
                recoveryURL.appending(path: "\(client.rawValue)/manifest.json"),
                recoveryURL.appending(path: "\(client.rawValue)/snapshot"),
                receiptsURL.appending(path: "\(client.rawValue).json"),
                receiptsURL.appending(path: "transitions/\(client.rawValue).json"),
            ]
        }
        let savedBytes = try protectedFiles.map { try Data(contentsOf: $0) }
        let savedModes = try protectedFiles.map {
            try FileManager.default.attributesOfItem(atPath: $0.path)[.posixPermissions] as? Int
        }
        let report = await fixture.coordinator().reconcile(
            helperExecutableURL: fixture.directory.appending(path: "missing"),
            workspaceURL: fixture.workspaceURL)
        #expect(report?.entries.map(\.outcome) == [.failed(.discovery), .failed(.discovery)])
        #expect(await fixture.runner.commands.map(\.arguments) == [["--version"], ["--version"]])
        for (index, fileURL) in protectedFiles.enumerated() {
            #expect(try Data(contentsOf: fileURL) == savedBytes[index])
            #expect(
                try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions]
                    as? Int == savedModes[index])
        }
    }
}
