import AnchorApplication
import AnchorDomain
import Foundation

public protocol SessionContextRecording: Sendable {
    func recordSessionContext(
        in revisions: [RecordedArtifactRevision], at instant: Date
    ) async throws
}

public struct StoredSessionContextRecorder: SessionContextRecording {
    private let contentStore: any ArtifactContentStore
    private let action: RecordSessionContextAction

    public init(contentStore: any ArtifactContentStore, action: RecordSessionContextAction) {
        self.contentStore = contentStore
        self.action = action
    }

    public func recordSessionContext(
        in revisions: [RecordedArtifactRevision], at instant: Date
    ) async throws {
        for revision in revisions where revision.artifact.isAgentSessionTranscript {
            guard let content = try await contentStore.content(forRevision: revision.revisionID)
            else { continue }

            _ = try await action.perform(
                RecordSessionContextRequest(
                    artifact: revision.artifact,
                    content: content,
                    contentHash: revision.contentHash,
                    recordedAt: instant
                ))
        }
    }
}
