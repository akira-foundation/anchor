import AnchorApplication
import AnchorPersistence
import AnchorPlatformAppleCloud
import AnchorPlatformMacOS
import AnchorStorage
import CloudKit
import Foundation
import Observation

@MainActor
@Observable
final class AnchorMacContextEngine {
    enum State: Equatable {
        case idle
        case watching(
            projectName: String,
            storage: ContextStorageChoice,
            indexedSessions: Int?,
            inferenceStatus: KnowledgeInferenceStatus,
            refusals: [String]
        )
        case noWorkspaceConfigured
        case failed(String)
    }

    static let iCloudContainerIdentifier = "iCloud.com.akira.anchor"

    private(set) var state: State = .idle
    var agentBootstrapReport: AgentClientBootstrapReport? { agentBootstrapLifecycle?.report }
    var isAgentBootstrapRunning: Bool { agentBootstrapLifecycle?.isRunning ?? false }
    var agentBootstrapWorkspaceURL: URL? { agentBootstrapLifecycle?.workspaceURL }
    var hasAgentBootstrapLifecycle: Bool { agentBootstrapLifecycle != nil }
    let helperExecutableURL: URL

    private let supportDirectoryURL: URL?
    private let agentBootstrapLifecycle: AgentClientBootstrapLifecycle?
    private let startWorkspaceObservation:
        (@MainActor @Sendable (ObservedWorkspace) async throws -> State)?
    private var coordinator: WorkspaceObservationCoordinator?
    private var assembledSessionContext: AssembledSessionContext?
    private var rebuildSessionContextIfInferenceBecameReady:
        ((KnowledgeInferenceStatus) async -> DiscoveredSessionContextRebuilder.Rebuild?)?
    private var isStarting = false

    init(
        supportDirectoryURL: URL?,
        agentBootstrapLifecycle: AgentClientBootstrapLifecycle?,
        helperExecutableURL: URL,
        startWorkspaceObservation:
            (@MainActor @Sendable (ObservedWorkspace) async throws -> State)? = nil
    ) {
        self.supportDirectoryURL = supportDirectoryURL
        self.agentBootstrapLifecycle = agentBootstrapLifecycle
        self.helperExecutableURL = helperExecutableURL
        self.startWorkspaceObservation = startWorkspaceObservation
    }

    static var defaultSupportDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Anchor")
    }

    static func configuredForProduction(
        supportDirectoryURL: URL?, applicationBundleURL: URL
    ) -> AnchorMacContextEngine {
        let helperExecutableURL =
            applicationBundleURL
            .appending(path: "Contents/Helpers/AnchorMCPServer")
        return AnchorMacContextEngine(
            supportDirectoryURL: supportDirectoryURL,
            agentBootstrapLifecycle: supportDirectoryURL.map {
                AgentClientBootstrapLifecycle(
                    coordinator: AgentClientBootstrapAssembly.makeCoordinator(
                        supportDirectoryURL: $0),
                    helperExecutableURL: helperExecutableURL)
            },
            helperExecutableURL: helperExecutableURL)
    }

    func start() async {
        guard coordinator == nil, !isStarting else { return }

        isStarting = true
        defer { isStarting = false }

        do {
            try await beginObserving()
        } catch {
            state = .failed(String(describing: error))
        }
    }

    func refreshRefusals() async {
        guard let coordinator,
            case .watching(
                let projectName, let storage, let indexedSessions, let inferenceStatus, _) =
                state
        else { return }
        let currentInferenceStatus = await assembledSessionContext?.inferenceStatus()
        let recovered = await rebuildSessionContextIfInferenceBecameReady?(inferenceStatus)

        if let recovered {
            await coordinator.recordRefusals(
                recovered.refusals.map { "indexing \($0.artifactName): \($0.description)" })
        }

        state = .watching(
            projectName: projectName,
            storage: storage,
            indexedSessions: recovered?.indexedSessions ?? indexedSessions,
            inferenceStatus: currentInferenceStatus ?? inferenceStatus,
            refusals: await coordinator.recordedRefusals
        )
    }

    func stop() async {
        await agentBootstrapLifecycle?.stop()
        await coordinator?.stopObserving()
        coordinator = nil
        assembledSessionContext = nil
        rebuildSessionContextIfInferenceBecameReady = nil
        state = .idle
    }

    func retryAgentBootstrap() {
        guard !isAgentBootstrapRunning, let supportDirectoryURL else { return }
        let configuration = ObservedWorkspaceConfiguration(
            fileURL: ObservedWorkspaceConfiguration.defaultFileURL(
                inSupportDirectoryAt: supportDirectoryURL))
        let observed = try? configuration.observedWorkspace()
        agentBootstrapLifecycle?.start(workspaceURL: observed?.workspaceURL)
    }

    private func beginObserving() async throws {
        guard let supportDirectoryURL else {
            state = .failed("This Mac has no Application Support directory to keep context in")
            return
        }

        let configuration = ObservedWorkspaceConfiguration(
            fileURL: ObservedWorkspaceConfiguration.defaultFileURL(
                inSupportDirectoryAt: supportDirectoryURL))

        guard let observed = try configuration.observedWorkspace() else {
            state = .noWorkspaceConfigured
            return
        }
        agentBootstrapLifecycle?.start(workspaceURL: observed.workspaceURL)
        if let startWorkspaceObservation {
            state = try await startWorkspaceObservation(observed)
            return
        }

        let device = try DeviceIdentityStore(
            fileURL: supportDirectoryURL.appending(path: "device.json")
        ).deviceCreatingIfNeeded(displayName: Host.current().localizedName ?? "Mac")

        let storage = await ContextStorageAssembly.assemble(
            reachingRemote: Self.reachCloudKit,
            localRootURL: supportDirectoryURL.appending(path: "storage"),
            key: try SynchronizedEncryptionKeyStore().keyCreatingIfNeeded()
        )

        let sessionFileIndex = await ContextEngineAssembly.makeSessionFileIndex(
            inSupportDirectoryAt: supportDirectoryURL)
        let readModel = try await ContextReadModelAssembly.openWriter(
            supportDirectoryURL: supportDirectoryURL,
            configurationURL: ObservedWorkspaceConfiguration.defaultFileURL(
                inSupportDirectoryAt: supportDirectoryURL),
            remoteReader: GitCommandRepositoryRemoteReader())
        let sessionContext = try await ContextEngineAssembly.makeSessionContext(
            storage: storage, inferringKnowledge: observed.infersKnowledge,
            database: readModel.database)
        let sessionsOnDisk = ContextEngineAssembly.sessionsOnDisk(
            forProject: observed.projectID,
            inWorkspaceAt: observed.workspaceURL,
            sessionFileIndex: sessionFileIndex
        )
        let rebuild = await sessionContext.rebuilder.rebuild(from: sessionsOnDisk, at: Date())
        let readModelRebuilder = ContextEngineAssembly.makeReadModelRebuilder(
            writer: readModel, storage: storage, sessionContext: sessionContext,
            sessionFileIndex: sessionFileIndex)
        let indexedSessions = try await readModelRebuilder.rebuild()
        let initialRefusals = rebuild.refusals.map {
            "indexing \($0.artifactName): \($0.description)"
        }

        let assembled = ContextEngineAssembly.makeCoordinator(
            device: device,
            observedWorkspace: observed,
            storage: storage,
            supportDirectoryURL: supportDirectoryURL,
            sessionFileIndex: sessionFileIndex,
            sessionContext: sessionContext.recorder,
            artifactIndex: sessionContext.artifactIndex,
            contextStatus: readModel.status,
            presenceSnapshot: readModel.presences,
            initialRefusals: initialRefusals
        )

        try await assembled.startObserving(
            workspaceAt: observed.workspaceURL, forProject: observed.projectID)

        coordinator = assembled
        assembledSessionContext = sessionContext
        rebuildSessionContextIfInferenceBecameReady = { previousStatus in
            guard case .unavailable = previousStatus,
                await sessionContext.inferenceStatus() == .ready
            else { return nil }
            do {
                let update = try await readModel.status.beginUpdate()
                let recovered = await sessionContext.rebuildSessionContextIfInferenceBecameReady(
                    after: previousStatus,
                    from: ContextEngineAssembly.sessionsOnDisk(
                        forProject: observed.projectID,
                        inWorkspaceAt: observed.workspaceURL,
                        sessionFileIndex: sessionFileIndex
                    ),
                    at: Date()
                )
                try await readModel.status.completeUpdate(
                    update, succeeded: recovered?.refusals.isEmpty ?? true)
                return recovered
            } catch {
                await assembled.recordRefusals(["updating context availability: \(error)"])
                return nil
            }
        }
        state = .watching(
            projectName: observed.projectName,
            storage: storage.choice,
            indexedSessions: indexedSessions,
            inferenceStatus: await sessionContext.inferenceStatus(),
            refusals: await assembled.recordedRefusals
        )
    }

    private static func reachCloudKit() async -> (any StorageProvider)? {
        let container = CKContainer(identifier: iCloudContainerIdentifier)

        guard let status = try? await container.accountStatus(), status == .available else {
            return nil
        }

        return CloudKitStorageProvider(database: CloudKitDatabase(container: container))
    }
}
