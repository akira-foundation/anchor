import AnchorApplication
import Foundation

public actor AgentClientBootstrapCoordinator {
    private let makeAction: @Sendable (URL) -> BootstrapInstalledAgentClientsAction
    private var precedingReconciliation: Task<AgentClientBootstrapReport, Never>?

    public init(action: BootstrapInstalledAgentClientsAction) {
        makeAction = { _ in action }
    }

    init(makeAction: @escaping @Sendable (URL) -> BootstrapInstalledAgentClientsAction) {
        self.makeAction = makeAction
    }

    public func reconcile(
        helperExecutableURL: URL, workspaceURL: URL?
    ) async -> AgentClientBootstrapReport? {
        guard let workspaceURL,
            let registration = AgentMCPRegistration(
                serverName: "anchor", helperExecutableURL: helperExecutableURL,
                workspaceURL: workspaceURL)
        else { return nil }
        let preceding = precedingReconciliation
        let makeAction = makeAction
        let reconciliation = Task {
            _ = await preceding?.value
            return await makeAction(registration.workspaceURL).perform(
                BootstrapInstalledAgentClientsRequest(registration: registration))
        }
        precedingReconciliation = reconciliation
        return await reconciliation.value
    }
}
