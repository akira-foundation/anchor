import AnchorApplication
import AnchorPlatformMacOS
import Foundation
import Testing

actor AnchorMacBootstrapConfigurer: AgentClientMCPConfiguring {
    nonisolated let client = AgentClient.claudeCode
    private(set) var workspaces: [URL] = []
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

actor AnchorMacObservationRecorder {
    private(set) var workspaces: [URL] = []
    private(set) var bootstrapRunningValues: [Bool] = []

    func record(workspaceURL: URL, bootstrapWasRunning: Bool) {
        workspaces.append(workspaceURL)
        bootstrapRunningValues.append(bootstrapWasRunning)
    }
}

@MainActor
struct AnchorMacBootstrapFixture {
    let directoryURL: URL
    let supportDirectoryURL: URL
    let firstWorkspaceURL: URL
    let configurer = AnchorMacBootstrapConfigurer()
    let observationRecorder = AnchorMacObservationRecorder()
    private let lifecycle: AgentClientBootstrapLifecycle

    init(workspaceName: String?) throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AnchorMac bootstrap \(UUID().uuidString)")
        supportDirectoryURL = directoryURL.appendingPathComponent("support")
        firstWorkspaceURL = directoryURL.appendingPathComponent("first workspace")
        try FileManager.default.createDirectory(
            at: supportDirectoryURL, withIntermediateDirectories: true)
        let helperURL = directoryURL.appendingPathComponent("AnchorMCPServer")
        lifecycle = AgentClientBootstrapLifecycle(
            coordinator: AgentClientBootstrapCoordinator(
                action: BootstrapInstalledAgentClientsAction(configurers: [configurer])),
            helperExecutableURL: helperURL)
        if let workspaceName {
            _ = try replaceWorkspace(name: workspaceName)
        }
    }

    func makeEngine() -> AnchorMacContextEngine {
        let lifecycle = lifecycle
        let observationRecorder = observationRecorder
        return AnchorMacContextEngine(
            supportDirectoryURL: supportDirectoryURL, agentBootstrapLifecycle: lifecycle,
            helperExecutableURL: lifecycle.helperExecutableURL,
            startWorkspaceObservation: { observedWorkspace in
                await observationRecorder.record(
                    workspaceURL: observedWorkspace.workspaceURL,
                    bootstrapWasRunning: lifecycle.isRunning)
                return .watching(
                    projectName: observedWorkspace.projectName, storage: .synchronized,
                    indexedSessions: 0, inferenceStatus: .disabled, refusals: [])
            })
    }

    func replaceWorkspace(name: String) throws -> URL {
        let workspaceURL = directoryURL.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let configurationURL = ObservedWorkspaceConfiguration.defaultFileURL(
            inSupportDirectoryAt: supportDirectoryURL)
        let configurationBytes = try JSONSerialization.data(withJSONObject: [
            "workspacePath": workspaceURL.path, "projectName": "Fixture Project",
            "infersKnowledge": false,
        ])
        try configurationBytes.write(to: configurationURL)
        return workspaceURL.standardizedFileURL
    }

    func waitForBootstrap(_ engine: AnchorMacContextEngine) async {
        while engine.isAgentBootstrapRunning { await Task.yield() }
    }

    func clean() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
