import AnchorApplication
import CryptoKit
import Foundation

struct AgentConfigurationFingerprint: Codable, Equatable, Sendable {
    let exists: Bool
    let sha256: String?

    init(bytes: Data?) {
        exists = bytes != nil
        sha256 = bytes.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
    }
}

struct AgentConfigurationRecoveryTransaction: Codable, Equatable, Sendable {
    let client: AgentClient
    let configurationURL: URL
    let originalExists: Bool
    let originalFingerprint: AgentConfigurationFingerprint
    let identifier: UUID

    var restorationTemporaryURL: URL {
        configurationURL.deletingLastPathComponent()
            .appendingPathComponent(".anchor-recovery-\(identifier.uuidString).pending")
    }
}

enum AgentConfigurationRecoveryResult: Equatable, Sendable {
    case noTransaction
    case restored
    case configurationChangedExternally
}

enum AgentConfigurationCheckpointFailure: Error, Equatable {
    case configurationChangedExternally
}

actor AgentConfigurationRecoveryStore {
    private struct Manifest: Codable {
        let version: Int
        let transaction: AgentConfigurationRecoveryTransaction
        let originalPermissions: Int?
        let lastMutationFingerprint: AgentConfigurationFingerprint
        let completionPending: Bool?
    }

    private let directoryURL: URL
    private let persistence: AgentBootstrapFilePersistence

    init(directoryURL: URL, persistence: AgentBootstrapFilePersistence = .init()) {
        self.directoryURL = directoryURL
        self.persistence = persistence
    }

    func begin(
        client: AgentClient, configurationURL: URL
    ) throws -> AgentConfigurationRecoveryTransaction {
        guard configurationURL.isFileURL else {
            throw AgentBootstrapPersistenceError.unsupportedConfiguration
        }
        guard try readManifest(for: client) == nil else {
            throw AgentBootstrapPersistenceError.transactionExists
        }
        let configurationURL = configurationURL.standardizedFileURL
        let originalBytes = try readConfiguration(configurationURL)
        let originalPermissions =
            try originalBytes.map { _ in
                try FileManager.default.attributesOfItem(atPath: configurationURL.path)[
                    .posixPermissions] as? Int
            } ?? nil
        let transaction = AgentConfigurationRecoveryTransaction(
            client: client, configurationURL: configurationURL,
            originalExists: originalBytes != nil,
            originalFingerprint: AgentConfigurationFingerprint(bytes: originalBytes),
            identifier: UUID())
        let clientDirectoryURL = clientDirectoryURL(for: client)
        try persistence.createDirectory(clientDirectoryURL)
        try cleanOrphanFiles(for: client)
        if let originalBytes {
            try persistence.replace(originalBytes, at: snapshotURL(for: client))
        }
        try writeManifest(
            Manifest(
                version: 1, transaction: transaction, originalPermissions: originalPermissions,
                lastMutationFingerprint: transaction.originalFingerprint, completionPending: nil))
        return transaction
    }

    func recordMutationState(
        for transaction: AgentConfigurationRecoveryTransaction,
        expectedFingerprint: AgentConfigurationFingerprint? = nil
    ) throws {
        let manifest = try requireManifest(for: transaction)
        guard manifest.completionPending != true else {
            throw AgentBootstrapPersistenceError.invalidRecord
        }
        if expectedFingerprint != nil {
            try persistence.checkpoint(.validatingMutationState(transaction.configurationURL))
        }
        let fingerprint = AgentConfigurationFingerprint(
            bytes: try readConfiguration(transaction.configurationURL))
        if let expectedFingerprint, fingerprint != expectedFingerprint {
            throw AgentConfigurationCheckpointFailure.configurationChangedExternally
        }
        try writeManifest(
            Manifest(
                version: 1, transaction: transaction,
                originalPermissions: manifest.originalPermissions,
                lastMutationFingerprint: expectedFingerprint ?? fingerprint, completionPending: nil)
        )
    }

    func complete(_ transaction: AgentConfigurationRecoveryTransaction) throws {
        guard try readManifest(for: transaction.client) != nil else {
            try persistence.removeFile(transaction.restorationTemporaryURL)
            return
        }
        let manifest = try requireManifest(for: transaction)
        if manifest.completionPending != true {
            try writeManifest(
                Manifest(
                    version: 1, transaction: transaction,
                    originalPermissions: manifest.originalPermissions,
                    lastMutationFingerprint: manifest.lastMutationFingerprint,
                    completionPending: true))
        }
        try finishCleanup(transaction)
    }

    func restore(
        _ transaction: AgentConfigurationRecoveryTransaction
    ) throws -> AgentConfigurationRecoveryResult {
        let manifest = try requireManifest(for: transaction)
        if manifest.completionPending == true {
            try finishCleanup(transaction)
            return .noTransaction
        }
        try persistence.removeFile(transaction.restorationTemporaryURL)
        let currentFingerprint = AgentConfigurationFingerprint(
            bytes: try readConfiguration(transaction.configurationURL))
        if currentFingerprint == transaction.originalFingerprint {
            if let originalPermissions = manifest.originalPermissions {
                let currentPermissions =
                    try FileManager.default.attributesOfItem(
                        atPath: transaction.configurationURL.path)[.posixPermissions] as? Int
                guard currentPermissions == originalPermissions else {
                    return .configurationChangedExternally
                }
            }
            try complete(transaction)
            return .restored
        }
        guard currentFingerprint == manifest.lastMutationFingerprint else {
            return .configurationChangedExternally
        }
        if transaction.originalExists {
            let originalBytes = try persistence.readIfPresent(
                snapshotURL(for: transaction.client))
            guard let originalBytes, let originalPermissions = manifest.originalPermissions,
                AgentConfigurationFingerprint(bytes: originalBytes)
                    == transaction.originalFingerprint
            else { throw AgentBootstrapPersistenceError.invalidRecord }
            try persistence.replace(
                originalBytes, at: transaction.configurationURL,
                permissions: originalPermissions,
                recoveryTemporaryURL: transaction.restorationTemporaryURL)
        }
        if !transaction.originalExists && currentFingerprint.exists {
            try persistence.removeFile(transaction.configurationURL)
        }
        guard
            AgentConfigurationFingerprint(
                bytes: try readConfiguration(transaction.configurationURL))
                == transaction.originalFingerprint
        else { throw AgentBootstrapPersistenceError.invalidRecord }
        try complete(transaction)
        return .restored
    }

    func recoverIncompleteTransaction(
        for client: AgentClient,
        configurationURL: URL
    ) throws -> AgentConfigurationRecoveryResult {
        guard let manifest = try readManifest(for: client) else {
            try cleanOrphanFiles(for: client)
            return .noTransaction
        }
        guard manifest.transaction.configurationURL == configurationURL.standardizedFileURL else {
            throw AgentBootstrapPersistenceError.invalidRecord
        }
        if manifest.completionPending == true {
            try finishCleanup(manifest.transaction)
            return .noTransaction
        }
        return try restore(manifest.transaction)
    }

    func requiresRestoration(for transaction: AgentConfigurationRecoveryTransaction) throws -> Bool
    {
        guard try readManifest(for: transaction.client) != nil else { return false }
        return try requireManifest(for: transaction).completionPending != true
    }

    private func cleanOrphanFiles(for client: AgentClient) throws {
        try persistence.removeFile(snapshotURL(for: client))
        try persistence.removePendingFiles(in: clientDirectoryURL(for: client))
    }

    private func finishCleanup(_ transaction: AgentConfigurationRecoveryTransaction) throws {
        try persistence.removeFile(transaction.restorationTemporaryURL)
        try cleanOrphanFiles(for: transaction.client)
        try persistence.removeFile(manifestURL(for: transaction.client))
    }

    private func readConfiguration(_ configurationURL: URL) throws -> Data? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: configurationURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw AgentBootstrapPersistenceError.unsupportedConfiguration
            }
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        return try persistence.readIfPresent(configurationURL)
    }

    private func requireManifest(
        for transaction: AgentConfigurationRecoveryTransaction
    ) throws -> Manifest {
        guard let manifest = try readManifest(for: transaction.client),
            manifest.transaction == transaction
        else {
            throw AgentBootstrapPersistenceError.invalidRecord
        }
        return manifest
    }

    private func readManifest(for client: AgentClient) throws -> Manifest? {
        guard let bytes = try persistence.readIfPresent(manifestURL(for: client))
        else { return nil }
        let manifest = try JSONDecoder().decode(Manifest.self, from: bytes)
        guard manifest.version == 1, manifest.transaction.client == client,
            manifest.transaction.configurationURL.isFileURL,
            manifest.transaction.originalExists == manifest.transaction.originalFingerprint.exists,
            manifest.transaction.originalExists == (manifest.originalPermissions != nil)
        else { throw AgentBootstrapPersistenceError.invalidRecord }
        if let permissions = manifest.originalPermissions, !(0...0o7777).contains(permissions) {
            throw AgentBootstrapPersistenceError.invalidRecord
        }
        return manifest
    }

    private func writeManifest(_ manifest: Manifest) throws {
        try persistence.replace(
            JSONEncoder().encode(manifest),
            at: manifestURL(for: manifest.transaction.client))
    }

    private func clientDirectoryURL(for client: AgentClient) -> URL {
        directoryURL.appendingPathComponent(client.rawValue, isDirectory: true)
    }

    private func manifestURL(for client: AgentClient) -> URL {
        clientDirectoryURL(for: client).appendingPathComponent("manifest.json")
    }

    private func snapshotURL(for client: AgentClient) -> URL {
        clientDirectoryURL(for: client).appendingPathComponent("snapshot")
    }
}
