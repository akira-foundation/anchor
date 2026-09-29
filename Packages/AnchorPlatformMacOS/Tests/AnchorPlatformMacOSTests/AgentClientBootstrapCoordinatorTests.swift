import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct AgentClientBootstrapCoordinatorTests {
    private let helperURL = URL(
        filePath: "/Applications/Anchor é.app/Contents/Helpers/AnchorMCPServer")
    private let workspaceURL = URL(filePath: "/projects/first workspace")

    @Test func absentWorkspaceDoesNotInvokeConfigurer() async {
        let spy = BootstrapCoordinatorSpy(client: .claudeCode)
        let coordinator = AgentClientBootstrapCoordinator(action: .init(configurers: [spy]))
        let report = await coordinator.reconcile(helperExecutableURL: helperURL, workspaceURL: nil)
        #expect(report == nil)
        #expect(await spy.registrations.isEmpty)
    }

    @Test func retriesFreshlyAndForwardsChangedWorkspace() async {
        let spy = BootstrapCoordinatorSpy(
            client: .claudeCode, outcomes: [.failed(.addition), .updated])
        let coordinator = AgentClientBootstrapCoordinator(action: .init(configurers: [spy]))
        let first = await coordinator.reconcile(
            helperExecutableURL: helperURL, workspaceURL: workspaceURL)
        let second = await coordinator.reconcile(
            helperExecutableURL: helperURL, workspaceURL: URL(filePath: "/projects/second é"))
        #expect(first?.entries.map(\.outcome) == [.failed(.addition)])
        #expect(second?.entries.map(\.outcome) == [.updated])
        let registrations = await spy.registrations
        #expect(registrations.map(\.definition.command) == [helperURL.path, helperURL.path])
        #expect(
            registrations.map(\.definition.arguments) == [
                ["--workspace", "/projects/first workspace"],
                ["--workspace", "/projects/second é"],
            ])
    }

    @Test func preservesIndependentClientOutcomes() async {
        let coordinator = AgentClientBootstrapCoordinator(
            action: .init(configurers: [
                BootstrapCoordinatorSpy(client: .claudeCode, outcomes: [.failed(.inspection)]),
                BootstrapCoordinatorSpy(client: .codex, outcomes: [.configured]),
            ]))
        let report = await coordinator.reconcile(
            helperExecutableURL: helperURL, workspaceURL: workspaceURL)
        #expect(report?.entries.map(\.client) == [.claudeCode, .codex])
        #expect(report?.entries.map(\.outcome) == [.failed(.inspection), .configured])
    }

    @Test func serializesOverlappingCallsAndReturnsEachReport() async {
        let spy = BootstrapCoordinatorSpy(
            client: .claudeCode, outcomes: [.configured, .alreadyConfigured], blocksFirst: true)
        let coordinator = AgentClientBootstrapCoordinator(action: .init(configurers: [spy]))
        let first = Task {
            await coordinator.reconcile(helperExecutableURL: helperURL, workspaceURL: workspaceURL)
        }
        await spy.waitForFirstCall()
        let second = Task {
            await coordinator.reconcile(helperExecutableURL: helperURL, workspaceURL: workspaceURL)
        }
        for _ in 0..<100 { await Task.yield() }
        #expect(await spy.registrations.count == 1)
        await spy.releaseFirstCall()
        #expect(await first.value?.entries.map(\.outcome) == [.configured])
        #expect(await second.value?.entries.map(\.outcome) == [.alreadyConfigured])
        #expect(await spy.maximumConcurrentCalls == 1)
    }
}

private actor BootstrapCoordinatorSpy: AgentClientMCPConfiguring {
    nonisolated let client: AgentClient
    var registrations: [AgentMCPRegistration] = []
    var maximumConcurrentCalls = 0
    private var activeCalls = 0
    private var outcomes: [AgentClientBootstrapOutcome]
    private let blocksFirst: Bool
    private var firstCallContinuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?

    init(
        client: AgentClient, outcomes: [AgentClientBootstrapOutcome] = [.configured],
        blocksFirst: Bool = false
    ) {
        self.client = client
        self.outcomes = outcomes
        self.blocksFirst = blocksFirst
    }

    func ensureUserRegistration(
        _ registration: AgentMCPRegistration
    ) async -> AgentClientBootstrapOutcome {
        registrations.append(registration)
        activeCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, activeCalls)
        let outcome = outcomes.removeFirst()
        if blocksFirst && registrations.count == 1 {
            await withCheckedContinuation { continuation in
                firstCallContinuation = continuation
                arrivalContinuation?.resume()
                arrivalContinuation = nil
            }
        }
        activeCalls -= 1
        return outcome
    }

    func waitForFirstCall() async {
        guard registrations.isEmpty else { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func releaseFirstCall() {
        firstCallContinuation?.resume()
        firstCallContinuation = nil
    }
}
