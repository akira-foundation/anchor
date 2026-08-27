import Foundation

public struct Artifact: Sendable, Hashable, Codable, Identifiable {
    public let id: ArtifactID
    public let projectID: ProjectID
    public let provider: AgentProvider
    public let name: String

    public init?(id: ArtifactID, projectID: ProjectID, provider: AgentProvider, name: String) {
        guard !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        self.id = id
        self.projectID = projectID
        self.provider = provider
        self.name = name
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedArtifact = Artifact(
            id: try container.decode(ArtifactID.self, forKey: .id),
            projectID: try container.decode(ProjectID.self, forKey: .projectID),
            provider: try container.decode(AgentProvider.self, forKey: .provider),
            name: try container.decode(String.self, forKey: .name)
        )

        guard let decodedArtifact else {
            throw DecodingError.dataCorruptedError(
                forKey: .name,
                in: container,
                debugDescription: "Artifact name is empty or padded with whitespace"
            )
        }

        self = decodedArtifact
    }
}
