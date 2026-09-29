import AnchorApplication
import Foundation

struct AgentMCPConfigurationMutationPipeline: Sendable {
    let client: AgentClient
    let configurationURL: URL
    private let receipts: AgentBootstrapReceiptStore
    private let recovery: AgentConfigurationRecoveryStore

    init(
        client: AgentClient, configurationURL: URL, receipts: AgentBootstrapReceiptStore,
        recovery: AgentConfigurationRecoveryStore
    ) {
        self.client = client
        self.configurationURL = configurationURL.standardizedFileURL
        self.receipts = receipts
        self.recovery = recovery
    }

    func recoverPendingState() async -> AgentClientBootstrapOutcome? {
        do {
            let recoveryOutcome = try await receipts.recoverConfigurationAndReceipt(
                for: client, configurationURL: configurationURL, recovery: recovery)
            return recoveryOutcome == .configurationChangedExternally ? .recoveryRequired : nil
        } catch {
            return .failed(.restoration)
        }
    }

    func loadReceipt() async throws -> AgentBootstrapReceipt? {
        try await receipts.load(for: client)
    }

    func configurationFingerprint() throws -> AgentConfigurationFingerprint {
        do {
            return AgentConfigurationFingerprint(bytes: try Data(contentsOf: configurationURL))
        } catch CocoaError.fileReadNoSuchFile {
            return AgentConfigurationFingerprint(bytes: nil)
        }
    }

    func reconcileMutation(
        inspectedFingerprint: AgentConfigurationFingerprint,
        previousReceipt: AgentBootstrapReceipt?, desiredDefinition: AgentMCPDefinition,
        successOutcome: AgentClientBootstrapOutcome,
        mutation: @Sendable (AgentMCPConfigurationMutation) async throws -> Void
    ) async -> AgentClientBootstrapOutcome {
        let transaction: AgentConfigurationRecoveryTransaction
        do {
            transaction = try await recovery.begin(
                client: client, configurationURL: configurationURL)
        } catch {
            return .failed(.backup)
        }
        guard transaction.originalFingerprint == inspectedFingerprint,
            (try? configurationFingerprint()) == inspectedFingerprint
        else {
            return .recoveryRequired
        }
        let desiredReceipt = AgentBootstrapReceipt(
            client: client, configurationPath: configurationURL.path,
            definition: desiredDefinition)
        do {
            try await receipts.beginTransition(
                transaction, previousReceipt: previousReceipt, desiredReceipt: desiredReceipt)
        } catch {
            return .failed(.backup)
        }

        let activeMutation = AgentMCPConfigurationMutation(
            transaction: transaction, initialFingerprint: inspectedFingerprint,
            configurationFingerprint: configurationFingerprint, recovery: recovery)
        do {
            try await mutation(activeMutation)
            try await receipts.record(desiredReceipt)
        } catch AgentMCPConfigurationMutationFailure.configurationChangedExternally {
            return .recoveryRequired
        } catch AgentMCPConfigurationMutationFailure.failed(let stage) {
            return await restore(transaction, failedStage: stage)
        } catch {
            return await restore(transaction, failedStage: .verification)
        }

        do {
            try await recovery.complete(transaction)
            try await receipts.finishTransition(transaction)
        } catch {
            return .failed(.restoration)
        }
        return successOutcome
    }

    private func restore(
        _ transaction: AgentConfigurationRecoveryTransaction,
        failedStage: AgentClientBootstrapFailureStage
    ) async -> AgentClientBootstrapOutcome {
        do {
            try await receipts.markRollback(transaction)
            guard try await recovery.restore(transaction) != .configurationChangedExternally else {
                return .recoveryRequired
            }
            try await receipts.finishTransition(transaction)
            return .failed(failedStage)
        } catch {
            return .failed(.restoration)
        }
    }
}

actor AgentMCPConfigurationMutation {
    private let transaction: AgentConfigurationRecoveryTransaction
    private var expectedFingerprint: AgentConfigurationFingerprint
    private let configurationFingerprint: @Sendable () throws -> AgentConfigurationFingerprint
    private let recovery: AgentConfigurationRecoveryStore

    init(
        transaction: AgentConfigurationRecoveryTransaction,
        initialFingerprint: AgentConfigurationFingerprint,
        configurationFingerprint: @escaping @Sendable () throws -> AgentConfigurationFingerprint,
        recovery: AgentConfigurationRecoveryStore
    ) {
        self.transaction = transaction
        expectedFingerprint = initialFingerprint
        self.configurationFingerprint = configurationFingerprint
        self.recovery = recovery
    }

    func applyMutation(
        at stage: AgentClientBootstrapFailureStage,
        operation: @Sendable () async throws -> Void
    ) async throws {
        let currentFingerprint: AgentConfigurationFingerprint
        do {
            currentFingerprint = try configurationFingerprint()
        } catch {
            throw AgentMCPConfigurationMutationFailure.failed(stage)
        }
        guard currentFingerprint == expectedFingerprint else {
            throw AgentMCPConfigurationMutationFailure.configurationChangedExternally
        }

        let operationFailed: Bool
        do {
            try await operation()
            operationFailed = false
        } catch {
            operationFailed = true
        }
        let mutationFingerprint: AgentConfigurationFingerprint
        do {
            mutationFingerprint = try configurationFingerprint()
            try await recovery.recordMutationState(
                for: transaction, expectedFingerprint: mutationFingerprint)
        } catch AgentConfigurationCheckpointFailure.configurationChangedExternally {
            throw AgentMCPConfigurationMutationFailure.configurationChangedExternally
        } catch {
            throw AgentMCPConfigurationMutationFailure.failed(stage)
        }
        expectedFingerprint = mutationFingerprint
        if operationFailed {
            throw AgentMCPConfigurationMutationFailure.failed(stage)
        }
    }

    func verifyConfiguration(
        _ operation: @Sendable () async throws -> Void
    ) async throws {
        do {
            try await operation()
        } catch {
            throw AgentMCPConfigurationMutationFailure.failed(.verification)
        }
        let verifiedFingerprint: AgentConfigurationFingerprint
        do {
            verifiedFingerprint = try configurationFingerprint()
        } catch {
            throw AgentMCPConfigurationMutationFailure.failed(.verification)
        }
        guard verifiedFingerprint == expectedFingerprint else {
            throw AgentMCPConfigurationMutationFailure.configurationChangedExternally
        }
    }
}

private enum AgentMCPConfigurationMutationFailure: Error {
    case configurationChangedExternally
    case failed(AgentClientBootstrapFailureStage)
}
