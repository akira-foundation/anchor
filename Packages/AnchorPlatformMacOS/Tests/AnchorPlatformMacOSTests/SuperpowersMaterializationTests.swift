import AnchorDomain
import AnchorProvider
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Superpowers materialization")
struct SuperpowersMaterializationTests {
    private let projectID = ProjectID()
    private let provider = SuperpowersArtifactProvider(workspaceURL: URL(filePath: "/unused"))

    private func makeArtifact(named name: String) throws -> Artifact {
        try #require(
            Artifact(id: ArtifactID(), projectID: projectID, provider: .superpowers, name: name))
    }

    @Test("an artifact is written at its own relative path under the destination")
    func anArtifactIsWrittenAtItsOwnRelativePathUnderTheDestination() async throws {
        let destination = try WorkspaceFixture.make([:])
        let artifact = try makeArtifact(named: "docs/superpowers/plans/00-indice.md")

        try await provider.materializeArtifact(
            artifact, content: Data("plan body".utf8), atDestination: destination
        )

        let written = destination.appending(path: "docs/superpowers/plans/00-indice.md")
        #expect(String(decoding: try Data(contentsOf: written), as: UTF8.self) == "plan body")
    }

    @Test("materializing the same artifact to two destinations writes both")
    func materializingTheSameArtifactToTwoDestinationsWritesBoth() async throws {
        let firstDestination = try WorkspaceFixture.make([:])
        let secondDestination = try WorkspaceFixture.make([:])
        let artifact = try makeArtifact(named: ".superpowers/sdd/design-review.md")
        let content = Data("review body".utf8)

        try await provider.materializeArtifact(
            artifact, content: content, atDestination: firstDestination)
        try await provider.materializeArtifact(
            artifact, content: content, atDestination: secondDestination)

        for destination in [firstDestination, secondDestination] {
            let written = destination.appending(path: ".superpowers/sdd/design-review.md")
            #expect(FileManager.default.fileExists(atPath: written.path()))
        }
    }

    @Test("materializing twice replaces the file rather than failing")
    func materializingTwiceReplacesTheFileRatherThanFailing() async throws {
        let destination = try WorkspaceFixture.make([:])
        let artifact = try makeArtifact(named: "docs/superpowers/plans/00-indice.md")

        try await provider.materializeArtifact(
            artifact, content: Data("first".utf8), atDestination: destination)
        try await provider.materializeArtifact(
            artifact, content: Data("second".utf8), atDestination: destination)

        let written = destination.appending(path: "docs/superpowers/plans/00-indice.md")
        #expect(String(decoding: try Data(contentsOf: written), as: UTF8.self) == "second")
    }

    @Test(
        "a name that would escape the destination is refused",
        arguments: [
            "../escaped.md",
            "docs/../../escaped.md",
            "/etc/passwd",
            "docs/superpowers/plans/../../../../escaped.md",
        ]
    )
    func aNameThatWouldEscapeTheDestinationIsRefused(_ name: String) async throws {
        let destination = try WorkspaceFixture.make([:])
        let artifact = try makeArtifact(named: name)

        await #expect(throws: SuperpowersMaterializationFailure.nameIsNotARelativePath(name)) {
            try await provider.materializeArtifact(
                artifact, content: Data("payload".utf8), atDestination: destination
            )
        }
    }

    @Test("nothing is written anywhere when the name is refused")
    func nothingIsWrittenAnywhereWhenTheNameIsRefused() async throws {
        let destination = try WorkspaceFixture.make([:])
        let artifact = try makeArtifact(named: "../escaped.md")

        _ = try? await provider.materializeArtifact(
            artifact, content: Data("payload".utf8), atDestination: destination
        )

        let escaped = destination.deletingLastPathComponent().appending(path: "escaped.md")
        #expect(!FileManager.default.fileExists(atPath: escaped.path()))
    }
}
