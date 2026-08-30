import AnchorDomain
import AnchorPersistence
import AnchorPlatformMacOS
import AnchorProvider
import Foundation
import Testing

@Suite("Remembering which rollout files were already read")
struct CodexSessionIndexTests {
    private let projectID = ProjectID()

    private func line(_ fields: [String: Any]) -> String {
        String(
            decoding: try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
            as: UTF8.self
        )
    }

    private func rollout(workingDirectory: String, saying text: String) -> String {
        [
            line([
                "type": "session_meta", "timestamp": "2026-08-12T00:50:05.000Z",
                "payload": [
                    "session_id": "019ff304-ca04-79a0-816a-267f4b5a1f85",
                    "cwd": workingDirectory, "thread_source": "user",
                ],
            ]),
            line([
                "type": "response_item", "timestamp": "2026-08-12T00:50:06.000Z",
                "payload": [
                    "type": "message", "role": "user", "id": "msg_1",
                    "content": [["type": "input_text", "text": text]],
                ],
            ]),
        ].joined(separator: "\n")
    }

    private func makeRoot(_ text: String) throws -> (root: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "anchor-codex-\(UUID().uuidString)")
        let day = root.appending(path: "2026/08/12")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let file = day.appending(path: "rollout-0.jsonl")
        try Data(text.utf8).write(to: file)

        return (root, file)
    }

    @Test("a file already read is answered from the index without being opened")
    func aFileAlreadyReadIsAnsweredFromTheIndexWithoutBeingOpened() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let (root, file) = try makeRoot(
            rollout(workingDirectory: workspace.path(), saying: "build it"))
        let index = try await SessionFileIndex(database: try SQLiteDatabase(fileURL: nil))
        let artifacts = CodexSessionArtifacts(root: root, index: index)

        let first = try await artifacts.discoveredArtifacts(
            forProject: projectID, inWorkspaceAt: workspace)
        try FileManager.default.removeItem(at: file)
        try Data("this is not a rollout at all".utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: file.path())

        let recorded = try await index.recordedFile(atPath: WorkspacePath.comparable(file))

        #expect(first.count == 1)
        #expect(recorded?.artifactName == first.first?.artifact.name)
        #expect(recorded?.contentHash == first.first?.contentHash.rawValue)
    }

    @Test("a file that changed is read again")
    func aFileThatChangedIsReadAgain() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let (root, file) = try makeRoot(
            rollout(workingDirectory: workspace.path(), saying: "first"))
        let index = try await SessionFileIndex(database: try SQLiteDatabase(fileURL: nil))
        let artifacts = CodexSessionArtifacts(root: root, index: index)

        let first = try await artifacts.discoveredArtifacts(
            forProject: projectID, inWorkspaceAt: workspace)
        try Data(rollout(workingDirectory: workspace.path(), saying: "second and longer").utf8)
            .write(to: file)
        let second = try await artifacts.discoveredArtifacts(
            forProject: projectID, inWorkspaceAt: workspace)

        #expect(first.first?.artifact.id == second.first?.artifact.id)
        #expect(first.first?.contentHash != second.first?.contentHash)
    }

    @Test("without an index every file is read, as before")
    func withoutAnIndexEveryFileIsRead() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let (root, _) = try makeRoot(
            rollout(workingDirectory: workspace.path(), saying: "build it"))

        let discovered = try await CodexSessionArtifacts(root: root).discoveredArtifacts(
            forProject: projectID, inWorkspaceAt: workspace)

        #expect(discovered.count == 1)
    }

    @Test("a file belonging to another project is not recorded")
    func aFileBelongingToAnotherProjectIsNotRecorded() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let (root, file) = try makeRoot(
            rollout(workingDirectory: "/Users/someone/elsewhere", saying: "build it"))
        let index = try await SessionFileIndex(database: try SQLiteDatabase(fileURL: nil))

        let discovered = try await CodexSessionArtifacts(root: root, index: index)
            .discoveredArtifacts(forProject: projectID, inWorkspaceAt: workspace)

        #expect(discovered.isEmpty)
        #expect(try await index.recordedFile(atPath: WorkspacePath.comparable(file)) == nil)
    }
}
