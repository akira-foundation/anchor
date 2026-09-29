import AnchorApplication
import Foundation

extension AgentBootstrapReceiptStore {
    private struct Transition: Codable {
        let version: Int
        let transaction: AgentConfigurationRecoveryTransaction
        let previousReceipt: AgentBootstrapReceipt?
        let desiredReceipt: AgentBootstrapReceipt
        let rollback: Bool
    }

    func beginTransition(
        _ transaction: AgentConfigurationRecoveryTransaction,
        previousReceipt: AgentBootstrapReceipt?, desiredReceipt: AgentBootstrapReceipt
    ) throws {
        guard try readTransition(for: transaction.client) == nil,
            desiredReceipt.client == transaction.client,
            desiredReceipt.configurationPath == transaction.configurationURL.path,
            previousReceipt == nil || previousReceipt?.client == transaction.client
        else { throw AgentBootstrapPersistenceError.invalidRecord }
        try writeTransition(
            Transition(
                version: 1, transaction: transaction, previousReceipt: previousReceipt,
                desiredReceipt: desiredReceipt, rollback: false))
    }

    func markRollback(_ transaction: AgentConfigurationRecoveryTransaction) throws {
        let transition = try requireTransition(transaction)
        guard !transition.rollback else { return }
        try writeTransition(
            Transition(
                version: 1, transaction: transaction, previousReceipt: transition.previousReceipt,
                desiredReceipt: transition.desiredReceipt, rollback: true))
    }

    func finishTransition(_ transaction: AgentConfigurationRecoveryTransaction) throws {
        let transition = try requireTransition(transaction)
        let receipt = transition.rollback ? transition.previousReceipt : transition.desiredReceipt
        if let receipt { try record(receipt) } else { try remove(for: transaction.client) }
        try persistence.removeFile(transitionURL(for: transaction.client))
    }

    func recoverConfigurationAndReceipt(
        for client: AgentClient, configurationURL: URL, recovery: AgentConfigurationRecoveryStore
    ) async throws -> AgentConfigurationRecoveryResult {
        let transition = try readTransition(for: client)
        if let transition {
            guard transition.transaction.configurationURL == configurationURL.standardizedFileURL
            else { throw AgentBootstrapPersistenceError.invalidRecord }
            if try await recovery.requiresRestoration(for: transition.transaction) {
                try markRollback(transition.transaction)
            }
        }
        let recovered = try await recovery.recoverIncompleteTransaction(
            for: client, configurationURL: configurationURL)
        guard recovered != .configurationChangedExternally else { return recovered }
        if let transition { try finishTransition(transition.transaction) }
        return recovered
    }

    private func requireTransition(
        _ transaction: AgentConfigurationRecoveryTransaction
    ) throws -> Transition {
        guard let transition = try readTransition(for: transaction.client),
            transition.transaction == transaction
        else { throw AgentBootstrapPersistenceError.invalidRecord }
        return transition
    }

    private func readTransition(for client: AgentClient) throws -> Transition? {
        guard let bytes = try persistence.readIfPresent(transitionURL(for: client)) else {
            return nil
        }
        let transition = try JSONDecoder().decode(Transition.self, from: bytes)
        guard transition.version == 1, transition.transaction.client == client,
            transition.desiredReceipt.client == client,
            transition.desiredReceipt.configurationPath
                == transition.transaction.configurationURL.path,
            transition.previousReceipt == nil || transition.previousReceipt?.client == client
        else { throw AgentBootstrapPersistenceError.invalidRecord }
        return transition
    }

    private func writeTransition(_ transition: Transition) throws {
        let transitionURL = transitionURL(for: transition.transaction.client)
        try persistence.createDirectory(transitionURL.deletingLastPathComponent())
        try persistence.removePendingFiles(in: transitionURL.deletingLastPathComponent())
        try persistence.replace(JSONEncoder().encode(transition), at: transitionURL)
    }

    private func transitionURL(for client: AgentClient) -> URL {
        directoryURL.appendingPathComponent("transitions", isDirectory: true)
            .appendingPathComponent("\(client.rawValue).json")
    }
}
