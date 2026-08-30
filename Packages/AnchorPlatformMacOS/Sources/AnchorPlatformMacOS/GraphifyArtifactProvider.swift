import AnchorDomain
import AnchorProvider
import Foundation

public struct GraphifyArtifactProvider: ArtifactDiscovering, ArtifactClassifying {
    static let outputDirectory = "graphify-out"
    static let carriedFileNames = ["graph.json", "GRAPH_REPORT.md"]
    private static let dataFileNames = ["graph.json"]

    private let workspaceURL: URL

    public init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
    }

    public func discoverArtifacts(
        forProject projectID: ProjectID
    ) async throws -> [DiscoveredArtifact] {
        Self.carriedFileNames.compactMap { fileName in
            discoveredArtifact(named: fileName, forProject: projectID)
        }
    }

    public func classifyKnowledgeEntries(
        in discoveredArtifact: DiscoveredArtifact,
        content: Data
    ) async throws -> [KnowledgeEntry] {
        let fileName = String(discoveredArtifact.artifact.name.split(separator: "/").last ?? "")
        guard !Self.dataFileNames.contains(fileName) else { return [] }
        guard let firstLine = ArtifactSummaryLine.firstNonEmptyLine(of: content) else { return [] }

        return [
            KnowledgeEntry(
                id: KnowledgeEntryID(),
                projectID: discoveredArtifact.artifact.projectID,
                kind: .summary,
                summaryText: firstLine,
                source: .artifact(discoveredArtifact.artifact.id),
                sourceContentHash: discoveredArtifact.contentHash,
                createdAt: Date()
            )
        ]
    }

    private func discoveredArtifact(
        named fileName: String,
        forProject projectID: ProjectID
    ) -> DiscoveredArtifact? {
        guard let content = try? Data(contentsOf: fileURL(named: fileName)) else { return nil }

        let name = "\(Self.outputDirectory)/\(fileName)"
        let artifact = Artifact(
            id: ArtifactID.derived(projectID: projectID, provider: .graphify, name: name),
            projectID: projectID,
            provider: .graphify,
            name: name,
            retention: .latestRevisionOnly
        )
        guard let artifact else { return nil }

        return DiscoveredArtifact(artifact: artifact, contentHash: ContentHash.digest(of: content))
    }

    private func fileURL(named fileName: String) -> URL {
        workspaceURL.appending(path: Self.outputDirectory).appending(path: fileName)
    }
}
