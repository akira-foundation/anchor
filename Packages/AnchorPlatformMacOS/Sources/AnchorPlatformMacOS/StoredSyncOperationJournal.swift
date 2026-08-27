import AnchorApplication
import AnchorDomain
import AnchorStorage
import Foundation

public struct StoredSyncOperationJournal: SyncOperationJournal {
    private static let operationsPrefix = "operations"

    private let storage: any StorageProvider

    public init(storage: any StorageProvider) {
        self.storage = storage
    }

    public func queueOperation(
        for revision: ArtifactRevision, storageKey: StorageKey
    ) async throws -> SyncOperation {
        let operation = SyncOperation(
            id: SyncOperationID(),
            artifactID: revision.artifactID,
            revisionID: revision.id,
            storageKey: storageKey,
            contentHash: revision.contentHash,
            state: .pending,
            queuedAt: Date()
        )
        try await append(operation)

        return operation
    }

    public func recordTransition(
        of operationID: SyncOperationID, to state: SyncOperationState
    ) async throws {
        guard let latest = try await history(of: operationID).last else { return }

        try await append(
            SyncOperation(
                id: latest.id,
                artifactID: latest.artifactID,
                revisionID: latest.revisionID,
                storageKey: latest.storageKey,
                contentHash: latest.contentHash,
                state: state,
                queuedAt: latest.queuedAt
            )
        )
    }

    public func history(of operationID: SyncOperationID) async throws -> [SyncOperation] {
        guard let prefix = operationPrefix(for: operationID) else { return [] }

        return try await entries(withPrefix: prefix).map(\.operation)
    }

    public func currentState(of operationID: SyncOperationID) async throws -> SyncOperationState? {
        try await history(of: operationID).last?.state
    }

    public func pendingOperations() async throws -> [SyncOperation] {
        try await latestEntryPerOperation().filter { $0.state == .pending }
    }

    public func recoverInterruptedOperations() async throws {
        for interrupted in try await latestEntryPerOperation() where interrupted.state == .uploading
        {
            try await recordTransition(of: interrupted.id, to: .pending)
        }
    }

    private func append(_ operation: SyncOperation) async throws {
        let sequence = try await entriesCount(for: operation.id) + 1
        guard let key = entryKey(for: operation.id, sequence: sequence) else { return }

        try await storage.putObject(
            StorageObject(key: key, contents: try JSONEncoder().encode(operation)),
            precondition: .none
        )
    }

    private func entriesCount(for operationID: SyncOperationID) async throws -> Int {
        guard let prefix = operationPrefix(for: operationID) else { return 0 }

        return try await storage.listObjects(withPrefix: prefix).count
    }

    private func latestEntryPerOperation() async throws -> [SyncOperation] {
        var latestByOperation: [SyncOperationID: (sequence: Int, operation: SyncOperation)] = [:]
        for entry in try await entries(withPrefix: nil) {
            let known = latestByOperation[entry.operation.id]
            guard known == nil || known!.sequence < entry.sequence else { continue }
            latestByOperation[entry.operation.id] = entry
        }

        return latestByOperation.values.map(\.operation)
    }

    private func entries(
        withPrefix prefix: StorageKey?
    ) async throws -> [(sequence: Int, operation: SyncOperation)] {
        var found: [(sequence: Int, operation: SyncOperation)] = []
        for metadata in try await storage.listObjects(withPrefix: prefix ?? operationsRoot()) {
            guard let stored = try await storage.object(for: metadata.key),
                let operation = try? JSONDecoder().decode(
                    SyncOperation.self, from: stored.object.contents
                ),
                let sequence = sequenceNumber(of: metadata.key)
            else {
                continue
            }
            found.append((sequence, operation))
        }

        return found.sorted { $0.sequence < $1.sequence }
    }

    private func sequenceNumber(of key: StorageKey) -> Int? {
        key.rawValue.split(separator: "/").last.flatMap { Int($0) }
    }

    private func operationsRoot() -> StorageKey? {
        StorageKey(rawValue: Self.operationsPrefix)
    }

    private func operationPrefix(for operationID: SyncOperationID) -> StorageKey? {
        StorageKey(rawValue: "\(Self.operationsPrefix)/\(operationID.rawValue)")
    }

    private func entryKey(for operationID: SyncOperationID, sequence: Int) -> StorageKey? {
        StorageKey(rawValue: "\(Self.operationsPrefix)/\(operationID.rawValue)/\(sequence)")
    }
}
