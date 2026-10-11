import Foundation

@testable import AnchorPlatformMacOS

struct ObserverStopGuard {
    let observer: FileSystemEventObserver
    let watchdog: Task<Void, Never>

    func release() {
        watchdog.cancel()
        Task { [observer] in await observer.stopObserving() }
    }
}

func scheduleObserverStop(
    _ observer: FileSystemEventObserver, after timeout: Duration,
    onTimeout: @escaping @Sendable () -> Void = {}
) -> ObserverStopGuard {
    ObserverStopGuard(
        observer: observer,
        watchdog: Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            onTimeout()
            await observer.stopObserving()
        })
}
