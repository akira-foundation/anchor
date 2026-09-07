import AnchorApplication
import AnchorDomain
import AnchorProvider
import Foundation

public struct DiscoveredSessionContextRebuilder: Sendable {
    private let actionPipeline: SessionContextActionPipeline

    public init(action: RecordSessionContextAction) {
        actionPipeline = SessionContextActionPipeline(action: action)
    }

    init(actionPipeline: SessionContextActionPipeline) {
        self.actionPipeline = actionPipeline
    }

    public struct Rebuild: Sendable, Hashable {
        public let indexedSessions: Int
        public let refusals: [SessionContextRefusal]
    }

    @discardableResult
    public func rebuild(
        from sessions: [(artifact: Artifact, content: Data)], at instant: Date
    ) async -> Rebuild {
        var indexedSessions = 0
        var refusals: [SessionContextRefusal] = []

        for session in sessions where session.artifact.isAgentSessionTranscript {
            do {
                guard
                    let report = try await actionPipeline.rebuildSessionContext(
                        RecordSessionContextRequest(
                            artifact: session.artifact,
                            content: session.content,
                            contentHash: ContentHash.digest(of: session.content),
                            recordedAt: instant
                        ))
                else { continue }

                guard case .indexed = report.outcome else { continue }

                indexedSessions += 1

                guard let description = report.knowledgeRefusal else { continue }

                refusals.append(
                    SessionContextRefusal(
                        artifactName: session.artifact.name, description: description))
            } catch {
                refusals.append(
                    SessionContextRefusal(
                        artifactName: session.artifact.name, description: "\(error)"))
            }
        }

        return Rebuild(indexedSessions: indexedSessions, refusals: refusals)
    }
}
