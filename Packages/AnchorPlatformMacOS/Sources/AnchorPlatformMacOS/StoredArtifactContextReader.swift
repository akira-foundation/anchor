import AnchorApplication
import AnchorDomain
import AnchorStorage
import CryptoKit
import Foundation

public struct StoredArtifactContextReader: ArtifactRevisionContentReading {
    private let storageURL: URL
    private let keyLoader: @Sendable () async throws -> SymmetricKey?

    public init(storageURL: URL, keyLoader: @escaping @Sendable () async throws -> SymmetricKey?) {
        self.storageURL = storageURL
        self.keyLoader = keyLoader
    }

    public func loadRevision(
        withIdentifier revisionID: RevisionID
    ) async throws -> ArtifactRevision? {
        let storage = try await encryptedStorage()
        return try await StoredArtifactRevisionJournal(
            storage: storage,
            contentStore: StoredArtifactContentStore(storage: storage)
        ).revision(withIdentifier: revisionID)
    }

    public func readContent(forRevision revisionID: RevisionID) async throws -> Data? {
        try await StoredArtifactContentStore(storage: encryptedStorage()).content(
            forRevision: revisionID)
    }

    private func encryptedStorage() async throws -> EncryptingStorageProvider {
        guard let key = try await keyLoader() else { throw ContextQueryFailure.contextUnavailable }
        return EncryptingStorageProvider(
            wrapping: FileSystemStorageProvider(rootURL: storageURL), key: key)
    }
}
