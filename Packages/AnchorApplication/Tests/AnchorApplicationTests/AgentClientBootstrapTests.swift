import Foundation
import Testing

@testable import AnchorApplication

@Suite("Agent client bootstrap")
struct AgentClientBootstrapTests {
    @Test("registration requires the stable server name and absolute paths")
    func registrationValidatesFixedInputs() throws {
        let helperExecutableURL = URL(fileURLWithPath: "/Applications/Anchor/bin/../bin/anchor-mcp")
        let workspaceURL = URL(fileURLWithPath: "/Developer/../Developer/anchor")
        let registration = try #require(
            AgentMCPRegistration(
                serverName: "anchor",
                helperExecutableURL: helperExecutableURL,
                workspaceURL: workspaceURL
            )
        )

        #expect(registration.definition.command == "/Applications/Anchor/bin/anchor-mcp")
        #expect(registration.definition.arguments == ["--workspace", "/Developer/anchor"])
        #expect(registration.definition.environment == [:])
        #expect(
            AgentMCPRegistration(
                serverName: "other",
                helperExecutableURL: helperExecutableURL,
                workspaceURL: workspaceURL
            ) == nil)
        #expect(
            AgentMCPRegistration(
                serverName: "anchor",
                helperExecutableURL: URL(string: "file:relative-helper")!,
                workspaceURL: workspaceURL
            ) == nil)
        #expect(
            AgentMCPRegistration(
                serverName: "anchor",
                helperExecutableURL: helperExecutableURL,
                workspaceURL: URL(string: "file:relative-workspace")!
            ) == nil)
    }

    @Test("bootstrap reports clients in canonical order despite injected order")
    func bootstrapUsesCanonicalClientOrder() async throws {
        let request = makeRequest()
        let codexConfigurer = StubAgentClientConfigurer(client: .codex, outcome: .configured)
        let claudeConfigurer = StubAgentClientConfigurer(
            client: .claudeCode, outcome: .alreadyConfigured)
        let action = BootstrapInstalledAgentClientsAction(configurers: [
            codexConfigurer,
            claudeConfigurer,
        ])

        let report = await action.perform(request)

        #expect(
            report.entries == [
                AgentClientBootstrapEntry(client: .claudeCode, outcome: .alreadyConfigured),
                AgentClientBootstrapEntry(client: .codex, outcome: .configured),
            ])
        let claudeRegistrations = await claudeConfigurer.receivedRegistrations
        let codexRegistrations = await codexConfigurer.receivedRegistrations
        #expect(claudeRegistrations == [request.registration])
        #expect(codexRegistrations == [request.registration])
    }

    @Test("one client failure does not suppress the other client")
    func bootstrapIsolatesClientFailures() async throws {
        let request = makeRequest()
        let claudeConfigurer = StubAgentClientConfigurer(
            client: .claudeCode, outcome: .failed(.inspection))
        let codexConfigurer = StubAgentClientConfigurer(client: .codex, outcome: .configured)
        let action = BootstrapInstalledAgentClientsAction(configurers: [
            claudeConfigurer,
            codexConfigurer,
        ])

        let report = await action.perform(request)

        #expect(
            report.entries == [
                AgentClientBootstrapEntry(client: .claudeCode, outcome: .failed(.inspection)),
                AgentClientBootstrapEntry(client: .codex, outcome: .configured),
            ])
        let codexRegistrations = await codexConfigurer.receivedRegistrations
        #expect(codexRegistrations == [request.registration])
    }

    @Test("duplicate configurers produce one entry and only the first is invoked")
    func duplicateConfigurersUseFirstRegistration() async throws {
        let request = makeRequest()
        let firstClaudeConfigurer = StubAgentClientConfigurer(
            client: .claudeCode, outcome: .configured)
        let secondClaudeConfigurer = StubAgentClientConfigurer(
            client: .claudeCode, outcome: .conflict)
        let codexConfigurer = StubAgentClientConfigurer(client: .codex, outcome: .updated)
        let action = BootstrapInstalledAgentClientsAction(configurers: [
            codexConfigurer,
            firstClaudeConfigurer,
            secondClaudeConfigurer,
        ])

        let report = await action.perform(request)

        #expect(
            report.entries == [
                AgentClientBootstrapEntry(client: .claudeCode, outcome: .configured),
                AgentClientBootstrapEntry(client: .codex, outcome: .updated),
            ])
        let firstRegistrations = await firstClaudeConfigurer.receivedRegistrations
        let duplicateRegistrations = await secondClaudeConfigurer.receivedRegistrations
        #expect(firstRegistrations == [request.registration])
        #expect(duplicateRegistrations.isEmpty)
    }

    @Test("bootstrap forwards the registration and preserves every outcome")
    func bootstrapPreservesAllOutcomes() async throws {
        let request = makeRequest()
        let outcomes: [AgentClientBootstrapOutcome] = [
            .alreadyConfigured,
            .configured,
            .updated,
            .notInstalled,
            .conflict,
            .failed(.inspection),
            .recoveryRequired,
        ]

        for outcome in outcomes {
            let configurer = StubAgentClientConfigurer(client: .codex, outcome: outcome)
            let action = BootstrapInstalledAgentClientsAction(configurers: [configurer])

            let report = await action.perform(request)

            #expect(report.entries == [AgentClientBootstrapEntry(client: .codex, outcome: outcome)])
            let receivedRegistrations = await configurer.receivedRegistrations
            #expect(receivedRegistrations == [request.registration])
        }
    }

    @Test("only configured and updated outcomes require restart")
    func restartPolicyIsExplicit() throws {
        #expect(AgentClientBootstrapOutcome.configured.requiresRestart)
        #expect(AgentClientBootstrapOutcome.updated.requiresRestart)
        #expect(!AgentClientBootstrapOutcome.alreadyConfigured.requiresRestart)
        #expect(!AgentClientBootstrapOutcome.notInstalled.requiresRestart)
        #expect(!AgentClientBootstrapOutcome.conflict.requiresRestart)
        #expect(!AgentClientBootstrapOutcome.failed(.verification).requiresRestart)
        #expect(!AgentClientBootstrapOutcome.recoveryRequired.requiresRestart)
    }

    private func makeRequest() -> BootstrapInstalledAgentClientsRequest {
        let registration = AgentMCPRegistration(
            serverName: "anchor",
            helperExecutableURL: URL(fileURLWithPath: "/Applications/Anchor/bin/anchor-mcp"),
            workspaceURL: URL(fileURLWithPath: "/Developer/anchor")
        )!
        return BootstrapInstalledAgentClientsRequest(registration: registration)
    }
}

private actor StubAgentClientConfigurer: AgentClientMCPConfiguring {
    let client: AgentClient
    let outcome: AgentClientBootstrapOutcome
    private(set) var receivedRegistrations: [AgentMCPRegistration] = []

    init(client: AgentClient, outcome: AgentClientBootstrapOutcome) {
        self.client = client
        self.outcome = outcome
    }

    func ensureUserRegistration(
        _ registration: AgentMCPRegistration
    ) async -> AgentClientBootstrapOutcome {
        receivedRegistrations.append(registration)
        return outcome
    }
}
