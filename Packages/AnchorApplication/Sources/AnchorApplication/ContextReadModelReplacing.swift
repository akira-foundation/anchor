import AnchorDomain

public enum ContextReplacementFailure: Error, Sendable, Equatable {
    case projectMismatch
    case invalidTranscript
}

public protocol ArtifactContextReplacing: Sendable {
    func replaceArtifactRevisions(
        _ revisions: [RecordedArtifactRevision], forProject projectID: ProjectID)
        async throws
}

public protocol ProjectTranscriptsReplacing: Sendable {
    func replaceTranscripts(
        _ transcripts: [AgentTranscript], forProject projectID: ProjectID) async throws
}
