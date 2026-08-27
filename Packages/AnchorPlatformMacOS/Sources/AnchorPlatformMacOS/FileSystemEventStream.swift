import CoreServices
import Foundation

enum FileSystemEventStream {
    private static let creationFlags = UInt32(
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
    )
    private static let coalescingLatency = 0.1

    static func start(
        at workspaceURL: URL,
        resumingFrom checkpoint: UInt64?,
        delivering observer: FileSystemEventObserver
    ) -> FSEventStreamRef? {
        let delivery = Unmanaged.passRetained(EventDelivery(observer: observer)).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: delivery,
            retain: nil,
            release: { Unmanaged<EventDelivery>.fromOpaque($0!).release() },
            copyDescription: nil
        )

        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, paths, _, _ in
                let delivery = Unmanaged<EventDelivery>.fromOpaque(info!).takeUnretainedValue()
                let changedPaths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                delivery.deliver(changedPaths)
            },
            &context,
            [workspaceURL.path()] as CFArray,
            checkpoint ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            coalescingLatency,
            creationFlags
        )
        guard let stream else {
            Unmanaged<EventDelivery>.fromOpaque(delivery).release()
            return nil
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global())
        FSEventStreamStart(stream)

        return stream
    }

    static func latestEventID(of stream: FSEventStreamRef) -> UInt64 {
        FSEventStreamGetLatestEventId(stream)
    }

    static func tearDown(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

private final class EventDelivery: Sendable {
    private let observer: FileSystemEventObserver

    init(observer: FileSystemEventObserver) {
        self.observer = observer
    }

    func deliver(_ paths: [String]) {
        Task { await observer.receivePaths(paths) }
    }
}
