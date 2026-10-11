import AnchorApplication
import AnchorDomain
import AnchorStorage
import Foundation

public struct StoredArtifactContentStore: ArtifactContentStore {
    private static let contentPrefix = "content"

    private let storage: any StorageProvider

    public init(storage: any StorageProvider) {
        self.storage = storage
    }

    public func storeContent(_ content: Data, forRevision revisionID: RevisionID) async throws {
        guard let key = storageKey(for: revisionID) else { return }

        try await storage.putObject(
            StorageObject(key: key, contents: content), precondition: .none
        )
    }

    public func content(forRevision revisionID: RevisionID) async throws -> Data? {
        guard let key = storageKey(for: revisionID) else { return nil }

        return try await storage.object(for: key)?.object.contents
    }

    public func dropContent(forRevision revisionID: RevisionID) async throws {
        guard let key = storageKey(for: revisionID) else { return }

        try await storage.deleteObject(for: key)
    }

    private func storageKey(for revisionID: RevisionID) -> StorageKey? {
        StorageKey(rawValue: "\(Self.contentPrefix)/\(revisionID.rawValue)")
    }
}
