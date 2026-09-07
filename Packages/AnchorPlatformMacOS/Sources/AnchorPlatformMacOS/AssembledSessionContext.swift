import AnchorDomain
import AnchorIntelligence
import AnchorSearch
import Foundation

public struct AssembledSessionContext: Sendable {
    public let search: any ContextSearching
    public let recorder: any SessionContextRecording
    public let rebuilder: DiscoveredSessionContextRebuilder
    let statementInference: (any StatementInferring)?
    private let inferenceRecovery = SessionInferenceRecovery()

    public func inferenceStatus() async -> KnowledgeInferenceStatus {
        guard let statementInference else { return .disabled }

        switch await statementInference.readiness() {
        case .ready:
            return .ready
        case .unavailable(let description):
            return .unavailable(description)
        }
    }

    public func rebuildSessionContextIfInferenceBecameReady(
        after previousStatus: KnowledgeInferenceStatus,
        from sessions: [(artifact: Artifact, content: Data)],
        at instant: Date
    ) async -> DiscoveredSessionContextRebuilder.Rebuild? {
        guard case .unavailable = previousStatus else { return nil }
        guard await inferenceStatus() == .ready else { return nil }

        return await inferenceRecovery.rebuildSessionContext(
            with: rebuilder, from: sessions, at: instant)
    }
}

private actor SessionInferenceRecovery {
    private var isRebuilding = false

    func rebuildSessionContext(
        with rebuilder: DiscoveredSessionContextRebuilder,
        from sessions: [(artifact: Artifact, content: Data)],
        at instant: Date
    ) async -> DiscoveredSessionContextRebuilder.Rebuild? {
        guard !isRebuilding else { return nil }

        isRebuilding = true
        defer { isRebuilding = false }

        return await rebuilder.rebuild(from: sessions, at: instant)
    }
}
