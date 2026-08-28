import AnchorApplication
import AnchorDomain
import AnchorPlatformMacOS
import AnchorProvider
import Foundation
import Testing

@Suite("Discovering Codex sessions as artifacts")
struct CodexSessionProviderTests {
    private let projectID = ProjectID()

    private func line(_ fields: [String: Any]) -> String {
        String(
            decoding: try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
            as: UTF8.self
        )
    }

    private func rollout(
        session: String, workingDirectory: String, threadSource: String, saying text: String
    ) -> String {
        [
            line([
                "type": "session_meta", "timestamp": "2026-08-12T00:50:05.000Z",
                "payload": [
                    "session_id": session, "cwd": workingDirectory,
                    "thread_source": threadSource,
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

    private func makeRoot(_ rollouts: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "anchor-codex-\(UUID().uuidString)")
        let day = root.appending(path: "2026/08/12")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)

        for (index, rollout) in rollouts.enumerated() {
            try Data(rollout.utf8).write(to: day.appending(path: "rollout-\(index).jsonl"))
        }

        return root
    }

    @Test("a session a person started in this workspace becomes an artifact")
    func aSessionAPersonStartedInThisWorkspaceBecomesAnArtifact() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let root = try makeRoot([
            rollout(
                session: "019ff304-ca04-79a0-816a-267f4b5a1f85",
                workingDirectory: workspace.path(), threadSource: "user", saying: "build it")
        ])

        let discovered = try await CodexSessionProvider(
            workspaceURL: workspace, artifacts: CodexSessionArtifacts(root: root)
        ).discoverArtifacts(forProject: projectID)

        #expect(discovered.count == 1)
        #expect(discovered.first?.artifact.provider == .codex)
        #expect(discovered.first?.artifact.name.hasPrefix("sessions/codex/") == true)
    }

    @Test("a session another agent spawned is left alone")
    func aSessionAnotherAgentSpawnedIsLeftAlone() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let root = try makeRoot([
            rollout(
                session: "019ff304-ca04-79a0-816a-267f4b5a1f85",
                workingDirectory: workspace.path(), threadSource: "subagent",
                saying: "assess this permission request")
        ])

        let discovered = try await CodexSessionProvider(
            workspaceURL: workspace, artifacts: CodexSessionArtifacts(root: root)
        ).discoverArtifacts(forProject: projectID)

        #expect(discovered.isEmpty)
    }

    @Test("a session from another project is left alone")
    func aSessionFromAnotherProjectIsLeftAlone() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let root = try makeRoot([
            rollout(
                session: "019ff304-ca04-79a0-816a-267f4b5a1f85",
                workingDirectory: "/Users/someone/another-project", threadSource: "user",
                saying: "build it")
        ])

        let discovered = try await CodexSessionProvider(
            workspaceURL: workspace, artifacts: CodexSessionArtifacts(root: root)
        ).discoverArtifacts(forProject: projectID)

        #expect(discovered.isEmpty)
    }

    @Test("the reader returns the same bytes the discovery hashed")
    func theReaderReturnsTheSameBytesTheDiscoveryHashed() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let root = try makeRoot([
            rollout(
                session: "019ff304-ca04-79a0-816a-267f4b5a1f85",
                workingDirectory: workspace.path(), threadSource: "user", saying: "build it")
        ])
        let artifacts = CodexSessionArtifacts(root: root)
        let discovered = try await CodexSessionProvider(
            workspaceURL: workspace, artifacts: artifacts
        ).discoverArtifacts(forProject: projectID)
        let name = try #require(discovered.first?.artifact.name)

        let content = try await CodexSessionContentReader(
            projectID: projectID, artifacts: artifacts
        ).readContent(ofArtifactNamed: name, inWorkspaceAt: workspace)

        #expect(ContentHash.digest(of: try #require(content)) == discovered.first?.contentHash)
    }

    @Test("a Claude session name is not answered by the Codex reader")
    func aClaudeSessionNameIsNotAnsweredByTheCodexReader() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])

        let content = try await CodexSessionContentReader(projectID: projectID)
            .readContent(
                ofArtifactNamed: "sessions/claude/73519afa-1fb1-40d5-8b26-beb76f968a20.json",
                inWorkspaceAt: workspace
            )

        #expect(content == nil)
    }
}
