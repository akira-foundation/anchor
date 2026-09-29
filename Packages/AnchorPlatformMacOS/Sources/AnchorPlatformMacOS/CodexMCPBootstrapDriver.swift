import AnchorApplication
import Foundation

actor CodexMCPBootstrapDriver: AgentClientMCPConfiguring {
    nonisolated let client = AgentClient.codex
    private let locator: any AgentExecutableLocating
    private let runner: any AgentCommandRunning
    private let configurationURL: URL
    private let configurationDirectoryURL: URL?
    private let defaultHomeDirectoryURL: URL
    private let mutationPipeline: AgentMCPConfigurationMutationPipeline
    private var precedingReconciliation: Task<AgentClientBootstrapOutcome, Never>?

    init(
        locator: any AgentExecutableLocating, runner: any AgentCommandRunning,
        configurationURL: URL, receipts: AgentBootstrapReceiptStore,
        recovery: AgentConfigurationRecoveryStore, configurationDirectoryURL: URL? = nil,
        defaultHomeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.locator = locator
        self.runner = runner
        self.configurationURL = configurationURL.standardizedFileURL
        self.configurationDirectoryURL = configurationDirectoryURL?.standardizedFileURL
        self.defaultHomeDirectoryURL = defaultHomeDirectoryURL.standardizedFileURL
        mutationPipeline = AgentMCPConfigurationMutationPipeline(
            client: .codex, configurationURL: configurationURL, receipts: receipts,
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
        let effectiveDirectoryURL =
            configurationDirectoryURL
            ?? defaultHomeDirectoryURL.appendingPathComponent(".codex")
        guard configurationURL.isFileURL, effectiveDirectoryURL.isFileURL,
            defaultHomeDirectoryURL.isFileURL,
            configurationURL.path
                == effectiveDirectoryURL.appendingPathComponent("config.toml").path
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

        let previousDefinition: AgentMCPDefinition?
        let previousReceipt: AgentBootstrapReceipt?
        let inspectedFingerprint: AgentConfigurationFingerprint
        do {
            inspectedFingerprint = try mutationPipeline.configurationFingerprint()
            previousDefinition = try await inspect(executableURL: executableURL)
            guard try mutationPipeline.configurationFingerprint() == inspectedFingerprint else {
                return .recoveryRequired
            }
            if previousDefinition == registration.definition { return .alreadyConfigured }
            previousReceipt = try await mutationPipeline.loadReceipt()
            if let previousDefinition {
                guard previousReceipt?.configurationPath == configurationURL.path,
                    previousReceipt?.definition == previousDefinition
                else { return .conflict }
            }
        } catch CodexMCPConfigurationFailure.unsupportedDefinition { return .conflict } catch {
            return .failed(.inspection)
        }

        let commandRunner = runner
        let configurationDirectoryURL = configurationDirectoryURL
        let defaultHomeDirectoryURL = defaultHomeDirectoryURL
        return await mutationPipeline.reconcileMutation(
            inspectedFingerprint: inspectedFingerprint, previousReceipt: previousReceipt,
            desiredDefinition: registration.definition,
            successOutcome: previousDefinition == nil ? .configured : .updated
        ) { mutation in
            try await mutation.applyMutation(at: .addition) {
                let output = try await commandRunner.run(
                    Self.command(
                        [
                            "mcp", "add", registration.serverName, "--",
                            registration.definition.command,
                        ] + registration.definition.arguments,
                        executableURL: executableURL,
                        configurationDirectoryURL: configurationDirectoryURL,
                        defaultHomeDirectoryURL: defaultHomeDirectoryURL))
                guard output.terminationStatus == 0 else { throw Failure.commandFailed }
            }
            try await mutation.verifyConfiguration {
                guard
                    try await Self.inspect(
                        executableURL: executableURL, runner: commandRunner,
                        configurationDirectoryURL: configurationDirectoryURL,
                        defaultHomeDirectoryURL: defaultHomeDirectoryURL)
                        == registration.definition
                else { throw Failure.verificationFailed }
            }
        }
    }

    private func inspect(executableURL: URL) async throws -> AgentMCPDefinition? {
        try await Self.inspect(
            executableURL: executableURL, runner: runner,
            configurationDirectoryURL: configurationDirectoryURL,
            defaultHomeDirectoryURL: defaultHomeDirectoryURL)
    }

    private static func inspect(
        executableURL: URL, runner: any AgentCommandRunning, configurationDirectoryURL: URL?,
        defaultHomeDirectoryURL: URL
    ) async throws -> AgentMCPDefinition? {
        let output = try await runner.run(
            command(
                ["mcp", "get", "anchor", "--json"], executableURL: executableURL,
                configurationDirectoryURL: configurationDirectoryURL,
                defaultHomeDirectoryURL: defaultHomeDirectoryURL))
        if output.terminationStatus == 1, output.standardOutput.isEmpty,
            output.standardError == Data("Error: No MCP server named 'anchor' found.\n".utf8)
        {
            return nil
        }
        guard output.terminationStatus == 0 else { throw Failure.commandFailed }
        return try CodexMCPConfigurationDecoder().definition(from: output.standardOutput)
    }

    private static func command(
        _ arguments: [String], executableURL: URL, configurationDirectoryURL: URL?,
        defaultHomeDirectoryURL: URL
    ) -> AgentCommand {
        AgentCommand(
            executableURL: executableURL, arguments: arguments,
            environment: configurationDirectoryURL.map { ["CODEX_HOME": $0.path] } ?? [:],
            workingDirectoryURL: defaultHomeDirectoryURL,
            removedEnvironmentKeys: configurationDirectoryURL == nil ? ["CODEX_HOME"] : [])
    }

    private enum Failure: Error {
        case commandFailed
        case verificationFailed
    }
}
