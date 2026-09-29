import AnchorApplication
import Foundation

actor ClaudeCodeMCPBootstrapDriver: AgentClientMCPConfiguring {
    nonisolated let client = AgentClient.claudeCode
    private let locator: any AgentExecutableLocating
    private let runner: any AgentCommandRunning
    private let configurationURL: URL
    private let workingDirectoryURL: URL
    private let configurationDirectoryURL: URL?
    private let defaultHomeDirectoryURL: URL
    private let mutationPipeline: AgentMCPConfigurationMutationPipeline
    private var precedingReconciliation: Task<AgentClientBootstrapOutcome, Never>?

    init(
        locator: any AgentExecutableLocating, runner: any AgentCommandRunning,
        configurationURL: URL, workingDirectoryURL: URL,
        receipts: AgentBootstrapReceiptStore, recovery: AgentConfigurationRecoveryStore,
        configurationDirectoryURL: URL? = nil,
        defaultHomeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.locator = locator
        self.runner = runner
        self.configurationURL = configurationURL.standardizedFileURL
        self.workingDirectoryURL = workingDirectoryURL.standardizedFileURL
        self.configurationDirectoryURL = configurationDirectoryURL?.standardizedFileURL
        self.defaultHomeDirectoryURL = defaultHomeDirectoryURL.standardizedFileURL
        mutationPipeline = AgentMCPConfigurationMutationPipeline(
            client: .claudeCode, configurationURL: configurationURL, receipts: receipts,
            recovery: recovery)
    }

    func ensureUserRegistration(
        _ registration: AgentMCPRegistration
    ) async -> AgentClientBootstrapOutcome {
        let preceding = precedingReconciliation
        let reconciliation = Task {
            _ = await preceding?.value
            return await reconcile(registration)
        }
        precedingReconciliation = reconciliation
        return await reconciliation.value
    }

    private func reconcile(
        _ registration: AgentMCPRegistration
    ) async -> AgentClientBootstrapOutcome {
        let effectiveDirectoryURL = configurationDirectoryURL ?? defaultHomeDirectoryURL
        guard configurationURL.isFileURL, workingDirectoryURL.isFileURL,
            effectiveDirectoryURL.isFileURL,
            configurationURL.path
                == effectiveDirectoryURL.appendingPathComponent(".claude.json").path
        else { return .failed(.inspection) }
        guard
            AgentExecutableFileValidation.isExecutableRegularFile(
                at: registration.helperExecutableURL)
        else {
            return await locator.locate(client) == nil ? .notInstalled : .failed(.discovery)
        }
        if let recoveryOutcome = await mutationPipeline.recoverPendingState() {
            return recoveryOutcome
        }
        guard let executableURL = await locator.locate(client) else { return .notInstalled }

        let reader = ClaudeUserMCPConfigurationReader(configurationURL: configurationURL)
        let previousDefinition: AgentMCPDefinition?
        let previousReceipt: AgentBootstrapReceipt?
        let inspectedFingerprint: AgentConfigurationFingerprint
        do {
            inspectedFingerprint = try mutationPipeline.configurationFingerprint()
            guard
                try reader.shadowingScopes(
                    named: registration.serverName, workingDirectoryURL: workingDirectoryURL
                ).isEmpty
            else { return .conflict }
            previousDefinition = try reader.definition(named: registration.serverName)
            if previousDefinition == registration.definition { return .alreadyConfigured }
            previousReceipt = try await mutationPipeline.loadReceipt()
            if let previousDefinition {
                guard previousReceipt?.configurationPath == configurationURL.path,
                    previousReceipt?.definition == previousDefinition
                else { return .conflict }
            }
        } catch ClaudeMCPConfigurationFailure.unsupportedDefinition { return .conflict } catch {
            return .failed(.inspection)
        }

        let commandRunner = runner
        let configurationDirectoryURL = configurationDirectoryURL
        let workingDirectoryURL = workingDirectoryURL
        return await mutationPipeline.reconcileMutation(
            inspectedFingerprint: inspectedFingerprint, previousReceipt: previousReceipt,
            desiredDefinition: registration.definition,
            successOutcome: previousDefinition == nil ? .configured : .updated
        ) { mutation in
            if previousDefinition != nil {
                try await mutation.applyMutation(at: .removal) {
                    let output = try await commandRunner.run(
                        Self.command(
                            ["mcp", "remove", "--scope", "user", registration.serverName],
                            executableURL: executableURL,
                            configurationDirectoryURL: configurationDirectoryURL,
                            workingDirectoryURL: workingDirectoryURL))
                    guard output.terminationStatus == 0 else { throw Failure.commandFailed }
                }
            }
            try await mutation.applyMutation(at: .addition) {
                let output = try await commandRunner.run(
                    Self.command(
                        [
                            "mcp", "add", "--scope", "user", "--transport", "stdio",
                            registration.serverName,
                            "--", registration.definition.command,
                        ] + registration.definition.arguments,
                        executableURL: executableURL,
                        configurationDirectoryURL: configurationDirectoryURL,
                        workingDirectoryURL: workingDirectoryURL))
                guard output.terminationStatus == 0 else { throw Failure.commandFailed }
            }
            try await mutation.verifyConfiguration {
                try Self.verify(
                    registration, reader: reader, workingDirectoryURL: workingDirectoryURL)
                let status = try await commandRunner.run(
                    Self.command(
                        ["mcp", "get", registration.serverName], executableURL: executableURL,
                        configurationDirectoryURL: configurationDirectoryURL,
                        workingDirectoryURL: workingDirectoryURL))
                guard status.terminationStatus == 0 else { throw Failure.commandFailed }
                try Self.verify(
                    registration, reader: reader, workingDirectoryURL: workingDirectoryURL)
            }
        }
    }

    private static func command(
        _ arguments: [String], executableURL: URL, configurationDirectoryURL: URL?,
        workingDirectoryURL: URL
    ) -> AgentCommand {
        AgentCommand(
            executableURL: executableURL, arguments: arguments,
            environment: configurationDirectoryURL.map { ["CLAUDE_CONFIG_DIR": $0.path] } ?? [:],
            workingDirectoryURL: workingDirectoryURL,
            removedEnvironmentKeys: configurationDirectoryURL == nil ? ["CLAUDE_CONFIG_DIR"] : [])
    }

    private static func verify(
        _ registration: AgentMCPRegistration, reader: ClaudeUserMCPConfigurationReader,
        workingDirectoryURL: URL
    ) throws {
        guard try reader.definition(named: registration.serverName) == registration.definition,
            try reader.shadowingScopes(
                named: registration.serverName, workingDirectoryURL: workingDirectoryURL
            ).isEmpty
        else { throw Failure.verificationFailed }
    }

    private enum Failure: Error {
        case commandFailed
        case verificationFailed
    }
}
