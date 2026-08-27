import AnchorProvider
import CoreServices
import Foundation

public actor FileSystemEventObserver: WorkspaceChangeObserving {
    public static let defaultSilenceWindow = Duration.milliseconds(300)

    private let silenceWindow: Duration
    private var stream: FSEventStreamRef?
    private var continuation: AsyncStream<WorkspaceChange>.Continuation?
    private var pendingPaths: Set<String> = []
    private var flushTask: Task<Void, Never>?
    private var workspaceURL: URL?

    public init(silenceWindow: Duration = FileSystemEventObserver.defaultSilenceWindow) {
        self.silenceWindow = silenceWindow
    }

    nonisolated public func observeWorkspaceChanges(
        at workspaceURL: URL
    ) -> AsyncStream<WorkspaceChange> {
        AsyncStream { continuation in
            Task { await self.startObserving(at: workspaceURL, continuation: continuation) }
        }
    }

    public func stopObserving() async {
        flushTask?.cancel()
        flushTask = nil
        stream.map(FileSystemEventStream.tearDown)
        stream = nil
        continuation?.finish()
        continuation = nil
        pendingPaths.removeAll()
    }

    func receivePaths(_ paths: [String]) {
        guard let workspaceURL else { return }

        let relativePaths = paths.compactMap {
            WorkspacePath.relativePath(of: $0, under: workspaceURL)
        }
        let watched = relativePaths.filter(WorkspacePath.isWatched)
        guard !watched.isEmpty else { return }

        pendingPaths.formUnion(watched)
        scheduleFlush()
    }

    private func startObserving(
        at workspaceURL: URL,
        continuation: AsyncStream<WorkspaceChange>.Continuation
    ) {
        self.workspaceURL = workspaceURL
        self.continuation = continuation
        stream = FileSystemEventStream.start(at: workspaceURL, delivering: self)
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [silenceWindow] in
            try? await Task.sleep(for: silenceWindow)
            guard !Task.isCancelled else { return }
            await self.flush()
        }
    }

    private func flush() {
        guard let workspaceURL, !pendingPaths.isEmpty else { return }

        continuation?.yield(
            WorkspaceChange(workspaceURL: workspaceURL, changedPaths: pendingPaths)
        )
        pendingPaths.removeAll()
    }
}
