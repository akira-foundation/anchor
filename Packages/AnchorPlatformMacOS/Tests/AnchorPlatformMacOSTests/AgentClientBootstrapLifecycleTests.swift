import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AgentClientBootstrapLifecycleTests {
    private let helperURL = URL(filePath: "/fixture/Anchor helper")
    private let workspaceURL = URL(filePath: "/fixture/first project")

    @Test func absentWorkspaceDoesNotScheduleReconciliation() async {
        let configurer = LifecycleConfigurer()
        let lifecycle = makeLifecycle(configurer)
        lifecycle.start(workspaceURL: nil)
        #expect(!lifecycle.isRunning)
        #expect(lifecycle.report == nil)
        #expect(await configurer.workspaces.isEmpty)
    }

    @Test func startReturnsWhileReconciliationIsBlockedAndRejectsDuplicates() async {
        let configurer = LifecycleConfigurer()
        let lifecycle = makeLifecycle(configurer)
        lifecycle.start(workspaceURL: workspaceURL)
        await configurer.waitForCall(1)
        #expect(lifecycle.isRunning)
        #expect(lifecycle.workspaceURL == workspaceURL)
        #expect(lifecycle.report == nil)
        lifecycle.start(workspaceURL: URL(filePath: "/fixture/duplicate"))
        await configurer.releaseCall(1, outcome: .failed(.addition))
        await waitForCompletion(lifecycle)
        #expect(lifecycle.report?.entries.map(\.outcome) == [.failed(.addition)])
        #expect(await configurer.workspaces == [workspaceURL])
        let nextWorkspace = URL(filePath: "/fixture/second é")
        lifecycle.start(workspaceURL: nextWorkspace)
        await configurer.waitForCall(2)
        await configurer.releaseCall(2, outcome: .updated)
        await waitForCompletion(lifecycle)
        #expect(lifecycle.report?.entries.map(\.outcome) == [.updated])
        #expect(lifecycle.workspaceURL == nextWorkspace)
        #expect(await configurer.workspaces == [workspaceURL, nextWorkspace])
    }

    @Test func stoppedCompletionCannotPublishOrClearRestartedRequest() async {
        let configurer = LifecycleConfigurer()
        let lifecycle = makeLifecycle(configurer)
        lifecycle.start(workspaceURL: workspaceURL)
        await configurer.waitForCall(1)
        let stopping = Task { await lifecycle.stop() }
        while lifecycle.isRunning { await Task.yield() }
        #expect(lifecycle.report == nil)
        #expect(lifecycle.workspaceURL == nil)
        let nextWorkspace = URL(filePath: "/fixture/restarted workspace")
        lifecycle.start(workspaceURL: nextWorkspace)
        await configurer.releaseCall(1, outcome: .failed(.inspection))
        await configurer.waitForCall(2)
        await stopping.value
        #expect(lifecycle.isRunning)
        #expect(lifecycle.report == nil)
        #expect(lifecycle.workspaceURL == nextWorkspace)
        lifecycle.start(workspaceURL: URL(filePath: "/fixture/rejected duplicate"))
        await configurer.releaseCall(2, outcome: .configured)
        await waitForCompletion(lifecycle)
        #expect(lifecycle.report?.entries.map(\.outcome) == [.configured])
        #expect(await configurer.workspaces == [workspaceURL, nextWorkspace])
        await lifecycle.stop()
        #expect(lifecycle.report == nil)
    }

    private func makeLifecycle(_ configurer: LifecycleConfigurer) -> AgentClientBootstrapLifecycle {
        AgentClientBootstrapLifecycle(
            coordinator: .init(action: .init(configurers: [configurer])),
            helperExecutableURL: helperURL)
    }

    private func waitForCompletion(_ lifecycle: AgentClientBootstrapLifecycle) async {
        while lifecycle.isRunning { await Task.yield() }
    }
}

private actor LifecycleConfigurer: AgentClientMCPConfiguring {
    nonisolated let client = AgentClient.claudeCode
    var workspaces: [URL] = []
    private var completions: [Int: CheckedContinuation<AgentClientBootstrapOutcome, Never>] = [:]
    private var arrivals: [Int: CheckedContinuation<Void, Never>] = [:]

    func ensureUserRegistration(
        _ registration: AgentMCPRegistration
    ) async -> AgentClientBootstrapOutcome {
        workspaces.append(registration.workspaceURL)
        let callNumber = workspaces.count
        return await withCheckedContinuation { continuation in
            completions[callNumber] = continuation
            arrivals.removeValue(forKey: callNumber)?.resume()
        }
    }

    func waitForCall(_ callNumber: Int) async {
        guard completions[callNumber] == nil else { return }
        await withCheckedContinuation { arrivals[callNumber] = $0 }
    }

    func releaseCall(_ callNumber: Int, outcome: AgentClientBootstrapOutcome) {
        completions.removeValue(forKey: callNumber)?.resume(returning: outcome)
    }
}
