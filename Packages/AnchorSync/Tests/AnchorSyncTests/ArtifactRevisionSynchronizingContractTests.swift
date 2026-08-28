import AnchorApplication
import Testing

private actor CountingArtifactRevisionSynchronizer: ArtifactRevisionSynchronizing {
    private(set) var completedSynchronizationCount = 0

    func synchronizePendingArtifactRevisions() async throws {
        completedSynchronizationCount += 1
    }
}

@Suite("ArtifactRevisionSynchronizing contract")
struct ArtifactRevisionSynchronizingContractTests {
    @Test("each synchronization request is recorded once")
    func eachSynchronizationRequestIsRecordedOnce() async throws {
        let artifactRevisionSynchronizer = CountingArtifactRevisionSynchronizer()

        try await artifactRevisionSynchronizer.synchronizePendingArtifactRevisions()
        try await artifactRevisionSynchronizer.synchronizePendingArtifactRevisions()

        #expect(await artifactRevisionSynchronizer.completedSynchronizationCount == 2)
    }
}
