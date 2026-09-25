import AnchorApplication
import AnchorDomain
import Foundation

public struct SessionContextRefusal: Sendable, Hashable {
    public let artifactName: String
    public let description: String

    public init(artifactName: String, description: String) {
        self.artifactName = artifactName
        self.description = description
    }
}

public protocol SessionContextRecording: Sendable {
    func recordSessionContext(
        in revisions: [RecordedArtifactRevision], at instant: Date
    ) async -> [SessionContextRefusal]
}

public struct StoredSessionContextRecorder: SessionContextRecording {
    private let contentStore: any ArtifactContentStore
    private let actionPipeline: SessionContextActionPipeline

    public init(contentStore: any ArtifactContentStore, action: RecordSessionContextAction) {
        self.contentStore = contentStore
        actionPipeline = SessionContextActionPipeline(action: action)
    }

    init(
        contentStore: any ArtifactContentStore,
        actionPipeline: SessionContextActionPipeline
    ) {
        self.contentStore = contentStore
        self.actionPipeline = actionPipeline
    }

    public func recordSessionContext(
        in revisions: [RecordedArtifactRevision], at instant: Date
    ) async -> [SessionContextRefusal] {
        var refusals: [SessionContextRefusal] = []

        for revision in revisions where revision.artifact.isAgentSessionTranscript {
            do {
                guard let content = try await contentStore.content(forRevision: revision.revisionID)
                else { throw ContextQueryFailure.entityNotFound }

                let report = try await actionPipeline.recordLiveSessionContext(
                    RecordSessionContextRequest(
                        artifact: revision.artifact,
                        content: content,
                        contentHash: revision.contentHash,
                        recordedAt: revision.revision.createdAt
                    ))

                guard let description = report.knowledgeRefusal else { continue }

                refusals.append(
                    SessionContextRefusal(
                        artifactName: revision.artifact.name, description: description))
            } catch {
                refusals.append(
                    SessionContextRefusal(
                        artifactName: revision.artifact.name, description: "\(error)"))
            }
        }

        return refusals
    }
}
