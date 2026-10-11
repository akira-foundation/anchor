import Foundation

@testable import AnchorPlatformMacOS

func scheduleObserverStop(
    _ observer: FileSystemEventObserver, after timeout: Duration
) -> Task<Void, Never> {
    Task {
        try? await Task.sleep(for: timeout)
        guard !Task.isCancelled else { return }
        await observer.stopObserving()
    }
}
