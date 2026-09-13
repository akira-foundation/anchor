import CoreServices
import Foundation

enum ObservationStartupFailure: Error {
    case creationFailed
    case registrationFailed
}

struct NativeFileSystemEventBatch: Sendable {
    let paths: [String]
    let flags: [UInt32]
    let eventIDs: [UInt64]
}

enum FileSystemEventStream {
    static func watchedPath(for workspaceURL: URL) -> String {
        workspaceURL.path(percentEncoded: false)
    }

    private static let creationFlags = UInt32(
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
    )
    private static let coalescingLatency = 0.1

    static func start(
        at workspaceURL: URL,
        resumingFrom checkpoint: UInt64?,
        observationID: UUID,
        delivering observer: FileSystemEventObserver,
        register: (FSEventStreamRef) -> Bool = FSEventStreamStart
    ) throws -> FSEventStreamRef {
        let delivery = Unmanaged.passRetained(
            EventDelivery(observer: observer, observationID: observationID)
        ).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: delivery,
            retain: nil,
            release: { Unmanaged<EventDelivery>.fromOpaque($0!).release() },
            copyDescription: nil
        )

        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, flags, eventIDs in
                let delivery = Unmanaged<EventDelivery>.fromOpaque(info!).takeUnretainedValue()
                let changedPaths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                delivery.deliver(
                    NativeFileSystemEventBatch(
                        paths: changedPaths,
                        flags: Array(UnsafeBufferPointer(start: flags, count: count)),
                        eventIDs: Array(UnsafeBufferPointer(start: eventIDs, count: count))))
            },
            &context,
            [Self.watchedPath(for: workspaceURL)] as CFArray,
            checkpoint ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            coalescingLatency,
            creationFlags
        )
        guard let stream else {
            Unmanaged<EventDelivery>.fromOpaque(delivery).release()
            throw ObservationStartupFailure.creationFailed
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "anchor.workspace-events"))
        guard register(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw ObservationStartupFailure.registrationFailed
        }

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
    private let continuation: AsyncStream<NativeFileSystemEventBatch>.Continuation
    private let deliveryTask: Task<Void, Never>

    init(observer: FileSystemEventObserver, observationID: UUID) {
        let channel = AsyncStream<NativeFileSystemEventBatch>.makeStream()
        continuation = channel.continuation
        deliveryTask = Task {
            for await batch in channel.stream {
                guard !Task.isCancelled else { return }
                await observer.receiveEvents(batch, forObservation: observationID)
            }
        }
    }

    deinit {
        continuation.finish()
        deliveryTask.cancel()
    }

    func deliver(_ batch: NativeFileSystemEventBatch) {
        continuation.yield(batch)
    }
}
