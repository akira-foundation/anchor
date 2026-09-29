import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct AgentClientBootstrapPresentationTests {
    @Test(arguments: [
        (AgentClientBootstrapOutcome.alreadyConfigured, "Configured", nil, false),
        (.configured, "Restart required", nil, false),
        (.updated, "Restart required", nil, false),
        (.notInstalled, "Not installed", nil, false),
        (.conflict, "Conflict", nil, true),
        (
            .failed(.addition), "Failed",
            "Close the client and check that its configuration can be updated, then retry.", true
        ),
        (
            .recoveryRequired, "Failed",
            "Close the client, review recent external configuration changes, then retry.", true
        ),
    ])
    func presentsApprovedStatusAndRetryEligibility(
        outcome: AgentClientBootstrapOutcome, status: String, guidance: String?, retry: Bool
    ) async throws {
        let registration = try #require(
            AgentMCPRegistration(
                serverName: "anchor", helperExecutableURL: URL(filePath: "/fixture/server"),
                workspaceURL: URL(filePath: "/fixture/project")))
        let report = await BootstrapInstalledAgentClientsAction(configurers: [
            PresentationConfigurer(client: .claudeCode, outcome: outcome),
            PresentationConfigurer(client: .codex, outcome: .alreadyConfigured),
        ]).perform(.init(registration: registration))
        let presentation = AgentClientBootstrapPresentation(report: report)
        #expect(presentation.rows.map(\.clientName) == ["Claude Code", "Codex"])
        #expect(presentation.rows.map(\.statusText) == [status, "Configured"])
        #expect(presentation.rows.map(\.guidanceText) == [guidance, nil])
        #expect(presentation.canRetry == retry)
    }

    @Test(arguments: [
        (
            AgentClientBootstrapFailureStage.discovery,
            "Make sure the client and Anchor helper are available, then retry."
        ),
        (
            .inspection,
            "Check that the client configuration is readable, then retry."
        ),
        (
            .backup,
            "Check that Anchor can write Application Support, then retry."
        ),
        (
            .removal,
            "Close the client and allow its existing Anchor registration to be updated, then retry."
        ),
        (
            .addition,
            "Close the client and check that its configuration can be updated, then retry."
        ),
        (
            .verification,
            "Restart the client, then retry the integration check."
        ),
        (
            .restoration,
            "Close the client, check configuration permissions, then retry recovery."
        ),
    ])
    func failedStagesHaveSafeSpecificGuidance(
        stage: AgentClientBootstrapFailureStage, guidance: String
    ) async throws {
        let report = try await report(outcome: .failed(stage))
        let row = try #require(AgentClientBootstrapPresentation(report: report).rows.first)
        #expect(row.statusText == "Failed")
        #expect(row.guidanceText == guidance)
        #expect(!guidance.contains("/"))
        #expect(!guidance.lowercased().contains("output"))
        #expect(!guidance.lowercased().contains("environment"))
        #expect(!guidance.lowercased().contains("snapshot"))
    }

    @Test func absentReportHasNoRowsOrRetry() {
        let presentation = AgentClientBootstrapPresentation(report: nil)
        #expect(presentation.rows.isEmpty)
        #expect(!presentation.canRetry)
    }

    private func report(
        outcome: AgentClientBootstrapOutcome
    ) async throws
        -> AgentClientBootstrapReport
    {
        let registration = try #require(
            AgentMCPRegistration(
                serverName: "anchor", helperExecutableURL: URL(filePath: "/fixture/server"),
                workspaceURL: URL(filePath: "/fixture/project")))
        return await BootstrapInstalledAgentClientsAction(configurers: [
            PresentationConfigurer(client: .claudeCode, outcome: outcome)
        ]).perform(.init(registration: registration))
    }
}

private struct PresentationConfigurer: AgentClientMCPConfiguring {
    let client: AgentClient
    let outcome: AgentClientBootstrapOutcome
    func ensureUserRegistration(
        _ registration: AgentMCPRegistration
    ) async -> AgentClientBootstrapOutcome { outcome }
}
