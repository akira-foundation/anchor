import AnchorDomain
import Foundation

public struct PublishedProjectDescriptor: Sendable, Hashable, Codable {
    public let projectID: ProjectID
    public let displayName: String
    public let canonicalRepositoryRemote: CanonicalRepositoryRemote?

    public init(
        projectID: ProjectID,
        displayName: String,
        canonicalRepositoryRemote: CanonicalRepositoryRemote?
    ) {
        self.projectID = projectID
        self.displayName = displayName
        self.canonicalRepositoryRemote = canonicalRepositoryRemote
    }
}

public struct PublishedArtifactDescriptor: Sendable, Hashable, Codable {
    public let artifactID: ArtifactID
    public let projectID: ProjectID
    public let provider: AgentProvider
    public let name: String

    public init(artifactID: ArtifactID, projectID: ProjectID, provider: AgentProvider, name: String)
    {
        self.artifactID = artifactID
        self.projectID = projectID
        self.provider = provider
        self.name = name
    }

    public init(artifact: Artifact) {
        self.init(
            artifactID: artifact.id, projectID: artifact.projectID, provider: artifact.provider,
            name: artifact.name)
    }
}

public struct KnowledgeSourceSnapshot: Sendable, Hashable, Codable {
    public let projectID: ProjectID
    public let source: KnowledgeEntrySource
    public let entries: [KnowledgeEntry]

    public init?(projectID: ProjectID, source: KnowledgeEntrySource, entries: [KnowledgeEntry]) {
        guard
            entries.allSatisfy({
                $0.projectID == projectID && $0.source == source && $0.state == .current
            })
        else { return nil }

        self.projectID = projectID
        self.source = source
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case projectID
        case source
        case entries
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSnapshot = KnowledgeSourceSnapshot(
            projectID: try container.decode(ProjectID.self, forKey: .projectID),
            source: try container.decode(KnowledgeEntrySource.self, forKey: .source),
            entries: try container.decode([KnowledgeEntry].self, forKey: .entries))

        guard let decodedSnapshot else {
            throw DecodingError.dataCorruptedError(
                forKey: .entries, in: container,
                debugDescription: "Snapshot entries belong to another source or are not current")
        }

        self = decodedSnapshot
    }
}

public struct PublishableProjectContext: Sendable, Hashable {
    public let project: PublishedProjectDescriptor
    public let artifacts: [Artifact]
    public let knowledgeEntries: [KnowledgeEntry]

    public init(
        project: PublishedProjectDescriptor, artifacts: [Artifact],
        knowledgeEntries: [KnowledgeEntry]
    ) {
        self.project = project
        self.artifacts = artifacts
        self.knowledgeEntries = knowledgeEntries
    }
}

public protocol PublishableProjectContextReading: Sendable {
    func loadPublishableProjectContext(
        forWorkspaceAt workspaceURL: URL
    ) async throws -> PublishableProjectContext?
}

public protocol ProjectDescriptorPublishing: Sendable {
    func publishProjectDescriptor(_ descriptor: PublishedProjectDescriptor) async throws
}

public protocol ArtifactDescriptorPublishing: Sendable {
    func publishArtifactDescriptor(_ artifact: Artifact) async throws
}

public protocol KnowledgeSnapshotPublishing: Sendable {
    func publishKnowledgeSnapshot(_ snapshot: KnowledgeSourceSnapshot) async throws
}
