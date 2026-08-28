import AnchorApplication
import AnchorDomain
import AnchorStorage
import Foundation

public struct StoredRevisionFeed: RemoteRevisionFeed {
    private static let revisionsPrefix = "revisions"

    private let storage: any StorageProvider

    public init(storage: any StorageProvider) {
        self.storage = storage
    }

    public func revisions(after cursor: String?) async throws -> RemoteRevisionPage {
        guard let prefix = StorageKey(rawValue: Self.revisionsPrefix) else {
            return RemoteRevisionPage(revisions: [], cursor: nil)
        }

        var found: [ArtifactRevision] = []
        for metadata in try await storage.listObjects(withPrefix: prefix) {
            guard let stored = try await storage.object(for: metadata.key),
                let revision = try? JSONDecoder().decode(
                    ArtifactRevision.self, from: stored.object.contents)
            else { continue }

            found.append(revision)
        }

        return RemoteRevisionPage(revisions: found, cursor: nil)
    }
}
