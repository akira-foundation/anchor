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
        case watching(projectName: String, storage: ContextStorageChoice, refusals: [String])
        case noWorkspaceConfigured
        case failed(String)
    }

    static let iCloudContainerIdentifier = "iCloud.com.akira.anchor"

    private(set) var state: State = .idle

    private let supportDirectoryURL: URL?
    private var coordinator: WorkspaceObservationCoordinator?
    private var isStarting = false

    init(supportDirectoryURL: URL? = AnchorMacContextEngine.defaultSupportDirectoryURL) {
        self.supportDirectoryURL = supportDirectoryURL
    }

    static var defaultSupportDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Anchor")
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
            case .watching(let projectName, let storage, _) = state
        else { return }

        state = .watching(
            projectName: projectName, storage: storage,
            refusals: await coordinator.recordedRefusals)
    }

    func stop() async {
        await coordinator?.stopObserving()
        coordinator = nil
        state = .idle
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

        let device = try DeviceIdentityStore(
            fileURL: supportDirectoryURL.appending(path: "device.json")
        ).deviceCreatingIfNeeded(displayName: Host.current().localizedName ?? "Mac")

        let storage = await ContextStorageAssembly.assemble(
            reachingRemote: Self.reachCloudKit,
            localRootURL: supportDirectoryURL.appending(path: "storage"),
            key: try SynchronizedEncryptionKeyStore().keyCreatingIfNeeded()
        )

        let assembled = ContextEngineAssembly.makeCoordinator(
            device: device,
            observedWorkspace: observed,
            storage: storage,
            supportDirectoryURL: supportDirectoryURL,
            sessionFileIndex: await ContextEngineAssembly.makeSessionFileIndex(
                inSupportDirectoryAt: supportDirectoryURL)
        )

        try await assembled.startObserving(
            workspaceAt: observed.workspaceURL, forProject: observed.projectID)

        coordinator = assembled
        state = .watching(
            projectName: observed.projectName, storage: storage.choice, refusals: [])
    }

    private static func reachCloudKit() async -> (any StorageProvider)? {
        let container = CKContainer(identifier: iCloudContainerIdentifier)

        guard let status = try? await container.accountStatus(), status == .available else {
            return nil
        }

        return CloudKitStorageProvider(database: CloudKitDatabase(container: container))
    }
}
