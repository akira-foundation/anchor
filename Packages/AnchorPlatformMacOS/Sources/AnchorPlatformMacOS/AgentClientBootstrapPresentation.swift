import AnchorApplication

public struct AgentClientBootstrapPresentation: Sendable {
    public struct Row: Sendable {
        public let client: AgentClient
        public let clientName: String
        public let statusText: String
        public let guidanceText: String?
    }

    public let rows: [Row]
    public let canRetry: Bool

    public init(report: AgentClientBootstrapReport?) {
        rows = (report?.entries ?? []).map { entry in
            Row(
                client: entry.client,
                clientName: entry.client == .claudeCode ? "Claude Code" : "Codex",
                statusText: Self.statusText(entry.outcome),
                guidanceText: Self.guidanceText(entry.outcome))
        }
        canRetry =
            report?.entries.contains {
                switch $0.outcome {
                case .conflict, .failed, .recoveryRequired: true
                case .alreadyConfigured, .configured, .updated, .notInstalled: false
                }
            } ?? false
    }

    private static func statusText(_ outcome: AgentClientBootstrapOutcome) -> String {
        switch outcome {
        case .alreadyConfigured: "Configured"
        case .configured, .updated: "Restart required"
        case .notInstalled: "Not installed"
        case .conflict: "Conflict"
        case .failed, .recoveryRequired: "Failed"
        }
    }

    private static func guidanceText(_ outcome: AgentClientBootstrapOutcome) -> String? {
        switch outcome {
        case .failed(.discovery):
            "Make sure the client and Anchor helper are available, then retry."
        case .failed(.inspection):
            "Check that the client configuration is readable, then retry."
        case .failed(.backup):
            "Check that Anchor can write Application Support, then retry."
        case .failed(.removal):
            "Close the client and allow its existing Anchor registration to be updated, then retry."
        case .failed(.addition):
            "Close the client and check that its configuration can be updated, then retry."
        case .failed(.verification):
            "Restart the client, then retry the integration check."
        case .failed(.restoration):
            "Close the client, check configuration permissions, then retry recovery."
        case .recoveryRequired:
            "Close the client, review recent external configuration changes, then retry."
        case .alreadyConfigured, .configured, .updated, .notInstalled, .conflict:
            nil
        }
    }
}
