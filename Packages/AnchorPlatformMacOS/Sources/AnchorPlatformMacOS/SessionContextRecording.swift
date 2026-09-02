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
    private let action: RecordSessionContextAction

    public init(contentStore: any ArtifactContentStore, action: RecordSessionContextAction) {
        self.contentStore = contentStore
        self.action = action
    }

    public func recordSessionContext(
        in revisions: [RecordedArtifactRevision], at instant: Date
    ) async -> [SessionContextRefusal] {
        var refusals: [SessionContextRefusal] = []

        for revision in revisions where revision.artifact.isAgentSessionTranscript {
            do {
                guard let content = try await contentStore.content(forRevision: revision.revisionID)
                else { continue }

                _ = try await action.perform(
                    RecordSessionContextRequest(
                        artifact: revision.artifact,
                        content: content,
                        contentHash: revision.contentHash,
                        recordedAt: instant
                    ))
            } catch {
                refusals.append(
                    SessionContextRefusal(
                        artifactName: revision.artifact.name, description: "\(error)"))
            }
        }

        return refusals
    }
}
