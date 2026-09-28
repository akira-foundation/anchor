import AnchorApplication
import AnchorPlatformMacOS
import Foundation
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AnchorMacAgentBootstrapIntegrationTests {
    @Test("the production composition root wires agent bootstrap")
    func productionCompositionRootWiresAgentBootstrap() {
        let contextEngine = AnchorMacContextEngine.configuredForProduction(
            supportDirectoryURL: URL(filePath: "/tmp/Anchor"),
            applicationBundleURL: URL(filePath: "/Applications/Anchor.app"))

        #expect(contextEngine.hasAgentBootstrapLifecycle)
        #expect(
            contextEngine.helperExecutableURL.path.hasSuffix(
                "Contents/Helpers/AnchorMCPServer"))
    }

    @Test(
        "resolved workspace starts bootstrap without blocking observation and reaches the menu model"
    )
    func bootstrapAndObservationRemainIndependent() async throws {
        let fixture = try AnchorMacBootstrapFixture(workspaceName: "first workspace")
        defer { fixture.clean() }
        let engine = fixture.makeEngine()

        await engine.start()
        await fixture.configurer.waitForCall(1)

        #expect(engine.isAgentBootstrapRunning)
        #expect(
            engine.state
                == .watching(
                    projectName: "Fixture Project", storage: .synchronized, indexedSessions: 0,
                    inferenceStatus: .disabled, refusals: []))
        #expect(await fixture.observationRecorder.bootstrapRunningValues == [true])
        await fixture.configurer.releaseCall(1, outcome: .failed(.addition))
        await fixture.waitForBootstrap(engine)

        let presentation = AgentClientBootstrapPresentation(report: engine.agentBootstrapReport)
        #expect(presentation.rows.map(\.statusText) == ["Failed"])
        #expect(
            presentation.rows.map(\.guidanceText) == [
                "Close the client and check that its configuration can be updated, then retry."
            ])
        #expect(presentation.canRetry)
    }

    @Test("no configured workspace starts neither bootstrap nor observation")
    func absentWorkspaceDoesNotMutateClients() async throws {
        let fixture = try AnchorMacBootstrapFixture(workspaceName: nil)
        defer { fixture.clean() }
        let engine = fixture.makeEngine()

        await engine.start()

        #expect(engine.state == .noWorkspaceConfigured)
        #expect(!engine.isAgentBootstrapRunning)
        #expect(engine.agentBootstrapReport == nil)
        #expect(await fixture.configurer.workspaces.isEmpty)
        #expect(await fixture.observationRecorder.workspaces.isEmpty)
    }

    @Test("retry is fresh, serialized, and reloads the configured workspace")
    func retryUsesCurrentWorkspaceOnce() async throws {
        let fixture = try AnchorMacBootstrapFixture(workspaceName: "first workspace")
        defer { fixture.clean() }
        let engine = fixture.makeEngine()
        await engine.start()
        await fixture.configurer.waitForCall(1)
        await fixture.configurer.releaseCall(1, outcome: .failed(.inspection))
        await fixture.waitForBootstrap(engine)

        let secondWorkspaceURL = try fixture.replaceWorkspace(name: "second é workspace")
        engine.retryAgentBootstrap()
        engine.retryAgentBootstrap()
        await fixture.configurer.waitForCall(2)
        #expect(engine.isAgentBootstrapRunning)
        #expect(
            await fixture.configurer.workspaces.map(\.path)
                == [fixture.firstWorkspaceURL.path, secondWorkspaceURL.path])

        await fixture.configurer.releaseCall(2, outcome: .updated)
        await fixture.waitForBootstrap(engine)
        #expect(engine.agentBootstrapReport?.entries.map(\.outcome) == [.updated])
        #expect(engine.agentBootstrapWorkspaceURL?.path == secondWorkspaceURL.path)
        #expect(await fixture.configurer.workspaces.count == 2)
    }
}
