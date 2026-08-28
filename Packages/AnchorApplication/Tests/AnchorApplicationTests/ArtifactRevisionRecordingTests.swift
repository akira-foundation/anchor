import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

@Suite("Recording an artifact revision")
struct ArtifactRevisionRecordingTests {
    private let deviceID = DeviceID()

    private func makeArtifact(retention: ArtifactRetention = .fullHistory) throws -> Artifact {
        try #require(
            Artifact(
                id: ArtifactID(), projectID: ProjectID(), provider: .superpowers,
                name: "docs/superpowers/plans/00-indice.md", retention: retention
            )
        )
    }

    @Test("unchanged content records nothing")
    func unchangedContentRecordsNothing() async throws {
        let artifact = try makeArtifact()
        let content = Data("unchanged".utf8)
        let journal = RecordingRevisionJournal()
        let recorder = ArtifactRevisionRecorder(
            journal: journal, contentStore: InMemoryArtifactContentStore(), deviceID: deviceID)

        _ = try await recorder.recordRevision(of: artifact, content: content)
        let second = try await recorder.recordRevision(of: artifact, content: content)

        #expect(second == nil)
        #expect(await journal.recordedRevisions.count == 1)
    }

    @Test("changed content records a revision whose parent is the one before it")
    func changedContentRecordsARevisionWhoseParentIsTheOneBeforeIt() async throws {
        let artifact = try makeArtifact()
        let journal = RecordingRevisionJournal()
        let recorder = ArtifactRevisionRecorder(
            journal: journal, contentStore: InMemoryArtifactContentStore(), deviceID: deviceID)

        let first = try #require(
            try await recorder.recordRevision(of: artifact, content: Data("one".utf8)))
        let second = try #require(
            try await recorder.recordRevision(of: artifact, content: Data("two".utf8)))

        #expect(first.parentRevisionID == nil)
        #expect(second.parentRevisionID == first.id)
    }

    @Test("a derivable artifact keeps no ancestry")
    func aDerivableArtifactKeepsNoAncestry() async throws {
        let artifact = try makeArtifact(retention: .latestRevisionOnly)
        let journal = RecordingRevisionJournal()
        let recorder = ArtifactRevisionRecorder(
            journal: journal, contentStore: InMemoryArtifactContentStore(), deviceID: deviceID)

        _ = try await recorder.recordRevision(of: artifact, content: Data("one".utf8))
        let second = try #require(
            try await recorder.recordRevision(of: artifact, content: Data("two".utf8)))

        #expect(second.parentRevisionID == nil)
    }

    @Test("a revision carries the device that produced it and the digest of what it saw")
    func aRevisionCarriesTheDeviceAndTheDigest() async throws {
        let artifact = try makeArtifact()
        let content = Data("body".utf8)
        let recorder = ArtifactRevisionRecorder(
            journal: RecordingRevisionJournal(),
            contentStore: InMemoryArtifactContentStore(),
            deviceID: deviceID
        )

        let revision = try #require(
            try await recorder.recordRevision(of: artifact, content: content))

        #expect(revision.deviceID == deviceID)
        #expect(revision.contentHash == ContentHash.digest(of: content))
        #expect(revision.artifactID == artifact.id)
    }

    @Test("the bytes a revision promises are kept when the revision is recorded")
    func bytesARevisionPromisesAreKeptWhenTheRevisionIsRecorded() async throws {
        let artifact = try makeArtifact()
        let contentStore = InMemoryArtifactContentStore()
        let recorder = ArtifactRevisionRecorder(
            journal: RecordingRevisionJournal(), contentStore: contentStore, deviceID: deviceID)

        let revision = try #require(
            try await recorder.recordRevision(of: artifact, content: Data("anchor".utf8)))

        #expect(try await contentStore.content(forRevision: revision.id) == Data("anchor".utf8))
    }

    @Test("content that returns to an earlier value still counts as a change")
    func contentThatReturnsToAnEarlierValueStillCountsAsAChange() async throws {
        let artifact = try makeArtifact()
        let journal = RecordingRevisionJournal()
        let recorder = ArtifactRevisionRecorder(
            journal: journal, contentStore: InMemoryArtifactContentStore(), deviceID: deviceID)

        _ = try await recorder.recordRevision(of: artifact, content: Data("one".utf8))
        _ = try await recorder.recordRevision(of: artifact, content: Data("two".utf8))
        let third = try await recorder.recordRevision(of: artifact, content: Data("one".utf8))

        #expect(third != nil)
        #expect(await journal.recordedRevisions.count == 3)
    }
}

private actor RecordingRevisionJournal: ArtifactRevisionJournal {
    private(set) var recordedRevisions: [ArtifactRevision] = []

    func latestRevision(forArtifact artifactID: ArtifactID) async throws -> ArtifactRevision? {
        recordedRevisions.last { $0.artifactID == artifactID }
    }

    func recordRevision(_ revision: ArtifactRevision) async throws {
        recordedRevisions.append(revision)
    }
}
