import AnchorApplication
import Foundation
import Observation

@MainActor
@Observable
public final class AgentClientBootstrapLifecycle {
    public private(set) var report: AgentClientBootstrapReport?
    public private(set) var isRunning = false
    public private(set) var workspaceURL: URL?
    public let helperExecutableURL: URL

    private let coordinator: AgentClientBootstrapCoordinator
    private var requestIdentifier: UUID?
    private var reconciliationTask: Task<Void, Never>?

    public init(coordinator: AgentClientBootstrapCoordinator, helperExecutableURL: URL) {
        self.coordinator = coordinator
        self.helperExecutableURL = helperExecutableURL
    }

    public func start(workspaceURL: URL?) {
        guard reconciliationTask == nil else { return }
        self.workspaceURL = workspaceURL
        guard let workspaceURL else {
            report = nil
            return
        }
        let identifier = UUID()
        requestIdentifier = identifier
        isRunning = true
        reconciliationTask = Task {
            let completedReport = await coordinator.reconcile(
                helperExecutableURL: helperExecutableURL, workspaceURL: workspaceURL)
            guard requestIdentifier == identifier, !Task.isCancelled else { return }
            report = completedReport
            isRunning = false
            reconciliationTask = nil
        }
    }

    public func stop() async {
        let stoppingTask = reconciliationTask
        requestIdentifier = nil
        reconciliationTask = nil
        isRunning = false
        report = nil
        workspaceURL = nil
        stoppingTask?.cancel()
        await stoppingTask?.value
    }
}
