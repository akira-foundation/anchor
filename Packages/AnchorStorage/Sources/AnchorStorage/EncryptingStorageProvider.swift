import AnchorDomain
import CryptoKit
import Foundation

public actor EncryptingStorageProvider: StorageProvider {
    private let wrapped: any StorageProvider
    private let key: SymmetricKey

    public init(wrapping wrapped: any StorageProvider, key: SymmetricKey) {
        self.wrapped = wrapped
        self.key = key
    }

    @discardableResult
    public func putObject(
        _ storageObject: StorageObject, precondition: StorageWritePrecondition
    ) async throws(StorageFailure) -> StorageObjectMetadata {
        guard let sealed = try? AES.GCM.seal(storageObject.contents, using: key).combined else {
            throw .contentUnreadable(storageObject.key)
        }

        return try await wrapped.putObject(
            StorageObject(key: storageObject.key, contents: sealed), precondition: precondition
        )
    }

    public func object(for key: StorageKey) async throws(StorageFailure) -> StoredObject? {
        guard let stored = try await wrapped.object(for: key) else { return nil }

        guard let sealed = try? AES.GCM.SealedBox(combined: stored.object.contents),
            let opened = try? AES.GCM.open(sealed, using: self.key)
        else { throw .contentUnreadable(key) }

        return StoredObject(
            object: StorageObject(key: key, contents: opened), metadata: stored.metadata
        )
    }

    public func deleteObject(for key: StorageKey) async throws(StorageFailure) {
        try await wrapped.deleteObject(for: key)
    }

    public func listObjects(
        withPrefix prefix: StorageKey?
    ) async throws(StorageFailure) -> [StorageObjectMetadata] {
        try await wrapped.listObjects(withPrefix: prefix)
    }

    public nonisolated func observeChanges(
        after cursor: StorageCursor?
    ) -> AsyncThrowingStream<StorageChange, any Error> {
        wrapped.observeChanges(after: cursor)
    }
}
