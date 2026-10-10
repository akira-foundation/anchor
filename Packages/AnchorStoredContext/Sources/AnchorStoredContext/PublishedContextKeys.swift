import AnchorDomain
import Foundation

public enum PublishedContextKeys {
    public static func artifactKey(for artifactID: ArtifactID) -> StorageKey? {
        StorageKey(rawValue: "artifacts/\(artifactID.rawValue)")
    }

    public static func projectKey(for projectID: ProjectID) -> StorageKey? {
        StorageKey(rawValue: "projects/\(projectID.rawValue)")
    }

    public static func knowledgeKey(
        for projectID: ProjectID, source: KnowledgeEntrySource
    ) throws -> StorageKey? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sourceDigest = ContentHash.digest(of: try encoder.encode(source))
        return StorageKey(rawValue: "knowledge/\(projectID.rawValue)/\(sourceDigest.rawValue)")
    }
}
