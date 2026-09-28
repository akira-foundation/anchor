public struct BootstrapInstalledAgentClientsRequest: Sendable {
    public let registration: AgentMCPRegistration

    public init(registration: AgentMCPRegistration) {
        self.registration = registration
    }
}

public struct BootstrapInstalledAgentClientsAction: Action {
    private let configurers: [any AgentClientMCPConfiguring]

    public init(configurers: [any AgentClientMCPConfiguring]) {
        self.configurers = configurers
    }

    public func perform(
        _ request: BootstrapInstalledAgentClientsRequest
    ) async -> AgentClientBootstrapReport {
        var entries: [AgentClientBootstrapEntry] = []
        for client in AgentClient.allCases {
            guard let configurer = configurers.first(where: { $0.client == client }) else {
                continue
            }
            let outcome = await configurer.ensureUserRegistration(request.registration)
            entries.append(AgentClientBootstrapEntry(client: client, outcome: outcome))
        }
        return AgentClientBootstrapReport(entries: entries)
    }
}
