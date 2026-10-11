import AnchorDomain
import AnchorStorage

actor PutCounter {
    private(set) var count = 0
    private var remainingFailures: Int

    init(failingFirstPuts: Int) {
        remainingFailures = failingFirstPuts
    }

    func increment() { count += 1 }

    func consumeFailure() -> Bool {
        guard remainingFailures > 0 else { return false }
        remainingFailures -= 1
        return true
    }
}

struct CountingStorageProvider: StorageProvider {
    let wrapped: any StorageProvider
    let counter: PutCounter

    init(wrapping wrapped: any StorageProvider, failingFirstPuts: Int = 0) {
        self.wrapped = wrapped
        counter = PutCounter(failingFirstPuts: failingFirstPuts)
    }

    var putCount: Int {
        get async { await counter.count }
    }

    func putObject(
        _ storageObject: StorageObject, precondition: StorageWritePrecondition
    ) async throws(StorageFailure) -> StorageObjectMetadata {
        guard await !counter.consumeFailure() else { throw .transportUnavailable }
        let metadata = try await wrapped.putObject(storageObject, precondition: precondition)
        await counter.increment()
        return metadata
    }

    func object(for key: StorageKey) async throws(StorageFailure) -> StoredObject? {
        try await wrapped.object(for: key)
    }

    func deleteObject(for key: StorageKey) async throws(StorageFailure) {
        try await wrapped.deleteObject(for: key)
    }

    func listObjects(
        withPrefix prefix: StorageKey?
    ) async throws(StorageFailure) -> [StorageObjectMetadata] {
        try await wrapped.listObjects(withPrefix: prefix)
    }

    func observeChanges(
        after cursor: StorageCursor?
    ) -> AsyncThrowingStream<StorageChange, any Error> {
        wrapped.observeChanges(after: cursor)
    }
}
