import AnchorFoundation

extension ArtifactID {
    public static func derived(
        projectID: ProjectID, provider: AgentProvider, name: String
    ) -> ArtifactID {
        derived(fromSeed: "\(projectID.rawValue)/\(provider.rawValue)/\(name)")
    }
}
