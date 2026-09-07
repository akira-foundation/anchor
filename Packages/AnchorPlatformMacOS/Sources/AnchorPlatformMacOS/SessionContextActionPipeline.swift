import AnchorApplication
import AnchorDomain

actor SessionContextActionPipeline {
    private struct LiveArtifactState {
        let contentHash: ContentHash
        var needsRecovery: Bool
    }

    private let action: RecordSessionContextAction
    private var precedingOperation: Task<Void, Never>?
    private var liveArtifacts: [ArtifactID: LiveArtifactState] = [:]

    init(action: RecordSessionContextAction) {
        self.action = action
    }

    func rebuildSessionContext(
        _ request: RecordSessionContextRequest
    ) async throws -> RecordSessionContextReport? {
        guard isEligibleForRebuild(request) else { return nil }

        let precedingOperation = precedingOperation
        let action = action
        let recording = Task { () throws -> RecordSessionContextReport? in
            await precedingOperation?.value
            guard isEligibleForRebuild(request) else { return nil }

            let report = try await action.recordSessionContext(request)
            recordRecovery(report, for: request)

            return report
        }
        self.precedingOperation = Task { _ = try? await recording.value }

        return try await recording.value
    }

    func recordLiveSessionContext(
        _ request: RecordSessionContextRequest
    ) async throws -> RecordSessionContextReport {
        liveArtifacts[request.artifact.id] = LiveArtifactState(
            contentHash: request.contentHash, needsRecovery: true)
        let precedingOperation = precedingOperation
        let action = action
        let recording = Task {
            await precedingOperation?.value

            let report = try await action.recordSessionContext(request)
            recordRecovery(report, for: request)

            return report
        }
        self.precedingOperation = Task { _ = try? await recording.value }

        return try await recording.value
    }

    private func isEligibleForRebuild(_ request: RecordSessionContextRequest) -> Bool {
        guard let liveArtifact = liveArtifacts[request.artifact.id] else { return true }

        return liveArtifact.contentHash == request.contentHash && liveArtifact.needsRecovery
    }

    private func recordRecovery(
        _ report: RecordSessionContextReport,
        for request: RecordSessionContextRequest
    ) {
        guard liveArtifacts[request.artifact.id]?.contentHash == request.contentHash else { return }

        liveArtifacts[request.artifact.id]?.needsRecovery = report.knowledgeRefusal != nil
    }
}
