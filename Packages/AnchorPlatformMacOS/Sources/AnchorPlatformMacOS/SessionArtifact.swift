import AnchorDomain
import AnchorProvider
import Foundation

public enum SessionArtifact {
    public static func make(
        from transcript: AgentTranscript, forProject projectID: ProjectID
    ) -> (artifact: Artifact, content: Data)? {
        let provider = transcript.session.provider
        let name = AgentSessionArtifactNaming.name(
            forSession: transcript.session.id, provider: provider)

        guard
            let artifact = Artifact(
                id: ArtifactID.derived(projectID: projectID, provider: provider, name: name),
                projectID: projectID,
                provider: provider,
                name: name,
                retention: .latestRevisionOnly
            ),
            let content = encode(transcript)
        else { return nil }

        return (artifact, content)
    }

    private static func encode(_ transcript: AgentTranscript) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try? encoder.encode(transcript.inConversationOrder)
    }
}
