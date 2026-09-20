import AnchorApplication
import AnchorDomain
import AnchorProvider
import Foundation

public struct ContextReadModelRebuilder: Sendable {
    private let projectID: ProjectID
    private let discoverer: any ArtifactDiscovering
    private let journal: any ArtifactRevisionJournal
    private let artifacts: any ArtifactContextReplacing
    private let transcripts: any ProjectTranscriptsReplacing
    private let canonicalSessions:
        @Sendable () async throws -> [(artifact: Artifact, content: Data)]
    private let status: ContextReadModelStatusStore

    public init(
        projectID: ProjectID, discoverer: any ArtifactDiscovering,
        journal: any ArtifactRevisionJournal,
        artifacts: any ArtifactContextReplacing, transcripts: any ProjectTranscriptsReplacing,
        canonicalSessions:
            @escaping @Sendable () async throws -> [(artifact: Artifact, content: Data)],
        status: ContextReadModelStatusStore
    ) {
        self.projectID = projectID
        self.discoverer = discoverer
        self.journal = journal
        self.artifacts = artifacts
        self.transcripts = transcripts
        self.canonicalSessions = canonicalSessions
        self.status = status
    }

    @discardableResult
    public func rebuild() async throws -> Int {
        let update = try await status.beginUpdate(rebuilding: true)
        let indexedSessions: Int
        do {
            let revisions = try await currentRevisions()
            let sessions = try await canonicalSessions()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let batch = try sessions.map { session in
                guard session.artifact.projectID == projectID else {
                    throw ContextReplacementFailure.projectMismatch
                }
                return try decoder.decode(AgentTranscript.self, from: session.content)
            }
            guard batch.allSatisfy({ $0.session.projectID == projectID }) else {
                throw ContextReplacementFailure.projectMismatch
            }
            try await artifacts.replaceArtifactRevisions(revisions, forProject: projectID)
            try await transcripts.replaceTranscripts(batch, forProject: projectID)
            indexedSessions = batch.count
        } catch {
            try await status.completeUpdate(update, succeeded: false)
            throw error
        }
        try await status.completeUpdate(update, succeeded: true)
        return indexedSessions
    }

    private func currentRevisions() async throws -> [RecordedArtifactRevision] {
        let discoveries = try await discoverer.discoverArtifacts(forProject: projectID)
        var revisions: [RecordedArtifactRevision] = []
        for discovery in discoveries {
            guard discovery.artifact.projectID == projectID else {
                throw ContextReplacementFailure.projectMismatch
            }
            guard
                let revision = try await journal.latestRevision(forArtifact: discovery.artifact.id)
            else { continue }
            guard revision.artifactID == discovery.artifact.id else {
                throw ContextQueryFailure.readFailed
            }
            revisions.append(
                RecordedArtifactRevision(artifact: discovery.artifact, revision: revision))
        }
        return revisions
    }
}
