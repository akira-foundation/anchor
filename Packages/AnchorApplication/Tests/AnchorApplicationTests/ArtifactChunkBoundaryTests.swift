import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

extension ContextQueryActionTests {
    @Test("artifact cursors bind artifact revision and scalar start offset")
    func artifactCursorsBindContentIdentity() async throws {
        let fixture = try ContextQueryFixture()
        let first = try await fixture.artifactAction.perform(
            try #require(ReadProjectArtifactRequest(artifactID: fixture.artifact.id, byteLimit: 4)))
        let unrelated = try ContextQueryFixture()
        await #expect(throws: ContextQueryFailure.invalidCursor) {
            try await unrelated.artifactAction.perform(
                try #require(
                    ReadProjectArtifactRequest(
                        artifactID: unrelated.artifact.id, cursor: first.nextCursor)))
        }
        for (revision, offset) in [
            (RevisionID(), 2), (fixture.revision.id, 3), (fixture.revision.id, 999),
        ] {
            let encoded = try JSONSerialization.data(withJSONObject: [
                "version": 1, "operation": "read-artifact",
                "project": fixture.project.projectID.rawValue,
                "artifact": fixture.artifact.id.rawValue, "revision": revision.rawValue,
                "offset": offset,
            ]).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            await #expect(throws: ContextQueryFailure.invalidCursor) {
                try await fixture.artifactAction.perform(
                    try #require(
                        ReadProjectArtifactRequest(
                            artifactID: fixture.artifact.id,
                            cursor: ContextPageCursor(rawValue: encoded))))
            }
        }
    }

    @Test("content readers may return a Data slice without changing byte coordinates")
    func contentSliceUsesRelativeByteOffsets() async throws {
        let fixture = try ContextQueryFixture()
        let sliced = Data("xxab😀cd".utf8).dropFirst(2)
        let action = ReadProjectArtifactAction(
            workspace: fixture, artifacts: fixture,
            content: QueryContentSpy(revision: fixture.revision, bytes: sliced),
            availability: fixture)
        let chunk = try await action.perform(
            try #require(ReadProjectArtifactRequest(artifactID: fixture.artifact.id, byteLimit: 4)))
        #expect(chunk.text == "ab")
    }
}
