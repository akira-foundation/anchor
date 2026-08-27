import AnchorDomain
import AnchorProvider
import Foundation

public enum ArtifactMaterializationFailure: Error, Sendable, Equatable {
    case nameIsNotARelativePath(String)
}

public struct FileSystemArtifactMaterializer: ArtifactMaterializing {
    public init() {}

    public func materializeArtifact(
        _ artifact: Artifact,
        content: Data,
        atDestination destinationURL: URL
    ) async throws {
        guard let relativeKey = StorageKey(rawValue: artifact.name) else {
            throw ArtifactMaterializationFailure.nameIsNotARelativePath(artifact.name)
        }

        let fileURL = destinationURL.appending(path: relativeKey.rawValue)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try content.write(to: fileURL, options: .atomic)
    }
}
