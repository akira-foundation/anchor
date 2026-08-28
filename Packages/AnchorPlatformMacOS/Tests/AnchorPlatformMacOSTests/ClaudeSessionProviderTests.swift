import AnchorApplication
import AnchorDomain
import AnchorPlatformMacOS
import AnchorProvider
import Foundation
import Testing

@Suite("Discovering Claude sessions as artifacts")
struct ClaudeSessionProviderTests {
    private let projectID = ProjectID()
    private let sessionID = "73519afa-1fb1-40d5-8b26-beb76f968a20"

    private func makeSessionsRoot(
        forWorkspaceAt workspaceURL: URL, transcript: String
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "anchor-claude-\(UUID().uuidString)")
        let directory = root.appending(
            path: ClaudeSessionsLocation.directoryName(forWorkspaceAt: workspaceURL))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(transcript.utf8).write(to: directory.appending(path: "\(UUID().uuidString).jsonl"))

        return root
    }

    private func transcriptLine(saying text: String) -> String {
        let fields: [String: Any] = [
            "type": "user", "sessionId": sessionID, "uuid": UUID().uuidString,
            "timestamp": "2026-08-08T18:20:24.411Z",
            "message": ["role": "user", "content": text],
        ]

        return String(
            decoding: try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
            as: UTF8.self
        )
    }

    @Test("a directory name turns both separators and dots into hyphens")
    func aDirectoryNameTurnsBothSeparatorsAndDotsIntoHyphens() {
        let name = ClaudeSessionsLocation.directoryName(
            forWorkspaceAt: URL(filePath: "/Users/kid/akira-io/node-sisp/.claude/worktrees/one"))

        #expect(name == "-Users-kid-akira-io-node-sisp--claude-worktrees-one")
    }

    @Test("a session becomes an artifact named after it")
    func aSessionBecomesAnArtifactNamedAfterIt() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let root = try makeSessionsRoot(
            forWorkspaceAt: workspace, transcript: transcriptLine(saying: "hello"))
        let provider = ClaudeSessionProvider(
            workspaceURL: workspace, artifacts: ClaudeSessionArtifacts(root: root))

        let discovered = try await provider.discoverArtifacts(forProject: projectID)

        #expect(discovered.count == 1)
        #expect(discovered.first?.artifact.provider == .claude)
        #expect(discovered.first?.artifact.retention == .latestRevisionOnly)
        #expect(discovered.first?.artifact.name.hasPrefix("sessions/claude/") == true)
    }

    @Test("discovering twice names the same artifact and the same content")
    func discoveringTwiceNamesTheSameArtifactAndTheSameContent() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let root = try makeSessionsRoot(
            forWorkspaceAt: workspace, transcript: transcriptLine(saying: "hello"))
        let provider = ClaudeSessionProvider(
            workspaceURL: workspace, artifacts: ClaudeSessionArtifacts(root: root))

        let first = try await provider.discoverArtifacts(forProject: projectID)
        let second = try await provider.discoverArtifacts(forProject: projectID)

        #expect(first.map(\.artifact.id) == second.map(\.artifact.id))
        #expect(first.map(\.contentHash) == second.map(\.contentHash))
    }

    @Test("the reader returns the same bytes the discovery hashed")
    func theReaderReturnsTheSameBytesTheDiscoveryHashed() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let root = try makeSessionsRoot(
            forWorkspaceAt: workspace, transcript: transcriptLine(saying: "hello"))
        let artifacts = ClaudeSessionArtifacts(root: root)
        let discovered = try await ClaudeSessionProvider(
            workspaceURL: workspace, artifacts: artifacts
        ).discoverArtifacts(forProject: projectID)
        let name = try #require(discovered.first?.artifact.name)

        let content = try await ClaudeSessionContentReader(
            projectID: projectID, artifacts: artifacts
        ).readContent(ofArtifactNamed: name, inWorkspaceAt: workspace)

        #expect(ContentHash.digest(of: try #require(content)) == discovered.first?.contentHash)
    }

    @Test("a workspace with no sessions discovers nothing")
    func aWorkspaceWithNoSessionsDiscoversNothing() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let root = FileManager.default.temporaryDirectory
            .appending(path: "anchor-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let discovered = try await ClaudeSessionProvider(
            workspaceURL: workspace, artifacts: ClaudeSessionArtifacts(root: root)
        ).discoverArtifacts(forProject: projectID)

        #expect(discovered.isEmpty)
    }
}

@Suite("Composing providers")
struct CompositeArtifactProviderTests {
    private let projectID = ProjectID()

    @Test("every provider in the composition is asked")
    func everyProviderInTheCompositionIsAsked() async throws {
        let workspace = try WorkspaceFixture.make([
            "docs/superpowers/plans/00-indice.md": "plan",
            "graphify-out/graph.json": "{}",
        ])

        let discovered = try await CompositeArtifactDiscoverer([
            SuperpowersArtifactProvider(workspaceURL: workspace),
            GraphifyArtifactProvider(workspaceURL: workspace),
        ]).discoverArtifacts(forProject: projectID)

        #expect(Set(discovered.map(\.artifact.provider)) == [.superpowers, .graphify])
    }

    @Test("the first reader that can answer is the one that answers")
    func theFirstReaderThatCanAnswerIsTheOneThatAnswers() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])

        let content = try await CompositeArtifactContentReader([
            ClaudeSessionContentReader(projectID: projectID),
            WorkspaceFileContentReader(),
        ]).readContent(
            ofArtifactNamed: "docs/superpowers/plans/00-indice.md", inWorkspaceAt: workspace)

        #expect(content == Data("plan".utf8))
    }

    @Test("a name no reader recognises comes back empty handed")
    func aNameNoReaderRecognisesComesBackEmptyHanded() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])

        let content = try await CompositeArtifactContentReader([
            ClaudeSessionContentReader(projectID: projectID),
            WorkspaceFileContentReader(),
        ]).readContent(ofArtifactNamed: "docs/nothing/here.md", inWorkspaceAt: workspace)

        #expect(content == nil)
    }
}
