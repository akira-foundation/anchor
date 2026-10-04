import AnchorPlatformMacOS

struct AnchorMacStatusPresentation {
    struct Row {
        let title: String
        let statusText: String
    }

    let projectName: String?
    let statusText: String
    let rows: [Row]
    let guidanceText: String?
    let diagnosticText: String?

    init(state: AnchorMacContextEngine.State) {
        switch state {
        case .idle:
            projectName = nil
            statusText = "Not watching"
            rows = []
            guidanceText = "Context collection starts when a configured workspace is available."
            diagnosticText = nil
        case .noWorkspaceConfigured:
            projectName = nil
            statusText = "Workspace required"
            rows = []
            guidanceText = "Configure a workspace to start collecting context."
            diagnosticText = nil
        case .failed(let description):
            projectName = nil
            statusText = "Stopped"
            rows = []
            guidanceText = "Review the failure in Details before restarting Anchor."
            diagnosticText = description
        case .watching(let name, let storage, let indexedSessions, let inference, let refusals):
            projectName = name
            statusText = refusals.isEmpty ? "Watching" : "Needs attention"
            rows = [
                Row(
                    title: "iCloud",
                    statusText: storage == .synchronized ? "Available" : "Local only"),
                Row(
                    title: "Search",
                    statusText: indexedSessions.map { "\($0) sessions searchable" } ?? "Unavailable"
                ),
                Row(title: "Knowledge", statusText: Self.inferenceStatusText(inference)),
            ]
            var guidance: [String] = []
            var diagnostics = refusals
            if storage == .localOnlyUntilAccountReturns {
                guidance.append("iCloud was unavailable at launch. Context is stored on this Mac.")
            }
            if indexedSessions == nil {
                guidance.append("The search index could not be built.")
            }
            if case .unavailable(let description) = inference {
                guidance.append("Knowledge inference is unavailable.")
                diagnostics.append(description)
            }
            if !refusals.isEmpty {
                guidance.append("Some context could not be recorded. Review Details.")
            }
            guidanceText = guidance.isEmpty ? nil : guidance.joined(separator: "\n")
            diagnosticText = diagnostics.isEmpty ? nil : diagnostics.joined(separator: "\n")
        }
    }

    private static func inferenceStatusText(_ status: KnowledgeInferenceStatus) -> String {
        switch status {
        case .disabled: "Disabled"
        case .ready: "Inference enabled"
        case .unavailable: "Unavailable"
        }
    }
}
