import AnchorDomain
import AnchorProvider
import Foundation

public enum SuperpowersMaterializationFailure: Error, Sendable, Equatable {
    case nameIsNotARelativePath(String)
}

extension SuperpowersArtifactProvider: ArtifactMaterializing {
    public func materializeArtifact(
        _ artifact: Artifact,
        content: Data,
        atDestination destinationURL: URL
    ) async throws {
        guard let relativeKey = StorageKey(rawValue: artifact.name) else {
            throw SuperpowersMaterializationFailure.nameIsNotARelativePath(artifact.name)
        }

        let fileURL = destinationURL.appending(path: relativeKey.rawValue)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try content.write(to: fileURL, options: .atomic)
    }
}
