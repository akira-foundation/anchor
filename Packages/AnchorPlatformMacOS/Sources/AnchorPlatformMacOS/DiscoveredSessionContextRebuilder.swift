import AnchorApplication
import AnchorDomain
import AnchorProvider
import Foundation

public struct DiscoveredSessionContextRebuilder: Sendable {
    private let action: RecordSessionContextAction

    public init(action: RecordSessionContextAction) {
        self.action = action
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
                let outcome = try await action.perform(
                    RecordSessionContextRequest(
                        artifact: session.artifact,
                        content: session.content,
                        contentHash: ContentHash.digest(of: session.content),
                        recordedAt: instant
                    ))

                guard case .indexed = outcome else { continue }

                indexedSessions += 1
            } catch {
                refusals.append(
                    SessionContextRefusal(
                        artifactName: session.artifact.name, description: "\(error)"))
            }
        }

        return Rebuild(indexedSessions: indexedSessions, refusals: refusals)
    }
}
