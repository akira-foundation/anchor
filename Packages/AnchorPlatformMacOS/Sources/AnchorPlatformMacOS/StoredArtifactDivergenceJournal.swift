import AnchorApplication
import AnchorDomain
import AnchorStorage
import Foundation

public struct StoredArtifactDivergenceJournal: ArtifactDivergenceJournal {
    private static let divergencesPrefix = "divergences"

    private let storage: any StorageProvider

    public init(storage: any StorageProvider) {
        self.storage = storage
    }

    public func recordDivergence(_ divergence: ArtifactDivergence) async throws {
        guard let key = storageKey(for: divergence) else { return }

        try await storage.putObject(
            StorageObject(key: key, contents: try JSONEncoder().encode(divergence)),
            precondition: .none
        )
    }

    public func pendingDivergences() async throws -> [ArtifactDivergence] {
        guard let prefix = StorageKey(rawValue: Self.divergencesPrefix) else { return [] }

        var found: [ArtifactDivergence] = []
        for metadata in try await storage.listObjects(withPrefix: prefix) {
            guard let stored = try await storage.object(for: metadata.key),
                let divergence = try? JSONDecoder().decode(
                    ArtifactDivergence.self, from: stored.object.contents)
            else { continue }

            found.append(divergence)
        }

        return found
    }

    private func storageKey(for divergence: ArtifactDivergence) -> StorageKey? {
        StorageKey(
            rawValue:
                "\(Self.divergencesPrefix)/\(divergence.artifactID.rawValue)"
                + "/\(divergence.remoteRevisionID.rawValue)"
        )
    }
}
