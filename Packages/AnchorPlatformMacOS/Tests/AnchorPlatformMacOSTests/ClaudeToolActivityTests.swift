import AnchorApplication
import AnchorDomain
import AnchorPlatformMacOS
import Foundation
import Testing

@Suite("Tool activity in a Claude transcript")
struct ClaudeToolActivityTests {
    private let reader = ClaudeTranscriptReader()
    private let projectID = ProjectID()
    private let session = "73519afa-1fb1-40d5-8b26-beb76f968a20"

    private func line(_ fields: [String: Any]) -> String {
        String(
            decoding: try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
            as: UTF8.self
        )
    }

    private func callLine(id: String, name: String, input: [String: Any]) -> String {
        line([
            "type": "assistant", "sessionId": session, "uuid": UUID().uuidString,
            "timestamp": "2026-08-08T18:20:24.411Z",
            "message": [
                "role": "assistant",
                "content": [["type": "tool_use", "id": id, "name": name, "input": input]],
            ],
        ])
    }

    private func resultLine(id: String, output: String, failed: Bool) -> String {
        line([
            "type": "user", "sessionId": session, "uuid": UUID().uuidString,
            "timestamp": "2026-08-08T18:20:30.000Z",
            "message": [
                "role": "user",
                "content": [
                    [
                        "type": "tool_result", "tool_use_id": id, "content": output,
                        "is_error": failed,
                    ]
                ],
            ],
        ])
    }

    @Test("a call and its result become one entry")
    func aCallAndItsResultBecomeOneEntry() throws {
        let text = [
            callLine(id: "toolu_1", name: "Bash", input: ["command": "swift test"]),
            resultLine(id: "toolu_1", output: "all tests passed", failed: false),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first)
        let activity = try #require(transcript.toolActivities.first)

        #expect(transcript.toolActivities.count == 1)
        #expect(activity.toolName == "Bash")
        #expect(activity.invocation.contains("swift test"))
        #expect(activity.outcome == "all tests passed")
        #expect(activity.failed == false)
    }

    @Test("a call whose result never arrived survives without one")
    func aCallWhoseResultNeverArrivedSurvivesWithoutOne() throws {
        let text = callLine(id: "toolu_1", name: "Bash", input: ["command": "swift test"])

        let transcript = try #require(
            reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first)

        #expect(transcript.toolActivities.first?.outcome == nil)
    }

    @Test("a call that failed is marked as failed")
    func aCallThatFailedIsMarkedAsFailed() throws {
        let text = [
            callLine(id: "toolu_1", name: "Bash", input: ["command": "redis-cli ping"]),
            resultLine(id: "toolu_1", output: "command not found", failed: true),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first)

        #expect(transcript.toolActivities.first?.failed == true)
    }

    @Test("thinking is not part of the record")
    func thinkingIsNotPartOfTheRecord() throws {
        let text = line([
            "type": "assistant", "sessionId": session, "uuid": UUID().uuidString,
            "timestamp": "2026-08-08T18:20:24.411Z",
            "message": [
                "role": "assistant",
                "content": [
                    ["type": "thinking", "thinking": "weighing the options"],
                    ["type": "text", "text": "done"],
                ],
            ],
        ])

        let transcript = try #require(
            reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first)

        #expect(transcript.entries.count == 1)
        #expect(transcript.messages.map(\.content) == ["done"])
    }

    @Test("a secret in the arguments or the output never reaches the record")
    func aSecretInTheArgumentsOrTheOutputNeverReachesTheRecord() throws {
        let text = [
            callLine(
                id: "toolu_1", name: "Bash",
                input: ["command": "psql postgresql://appuser:hunter2secret@db/anchor"]),
            resultLine(
                id: "toolu_1", output: "connected as postgresql://appuser:hunter2secret@db/anchor",
                failed: false),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first)
        let activity = try #require(transcript.toolActivities.first)

        #expect(activity.invocation.contains("hunter2secret") == false)
        #expect(activity.outcome?.contains("hunter2secret") == false)
    }

    @Test("the same call keeps the same identity across reads")
    func theSameCallKeepsTheSameIdentityAcrossReads() throws {
        let text = callLine(id: "toolu_1", name: "Bash", input: ["command": "swift test"])

        let first = reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first
        let second = reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first

        #expect(first?.toolActivities.map(\.id) == second?.toolActivities.map(\.id))
    }

    @Test("a huge command output arrives abridged")
    func aHugeCommandOutputArrivesAbridged() throws {
        let output = (1...3000).map { "line \($0) of build output" }.joined(separator: "\n")
        let text = [
            callLine(id: "toolu_1", name: "Bash", input: ["command": "swift build"]),
            resultLine(id: "toolu_1", output: output, failed: false),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first)
        let outcome = try #require(transcript.toolActivities.first?.outcome)

        #expect(outcome.utf8.count < output.utf8.count)
        #expect(outcome.hasPrefix("line 1 of build output"))
        #expect(outcome.contains("[omitted "))
    }

    @Test("a screenshot result becomes a description instead of its bytes")
    func aScreenshotResultBecomesADescriptionInsteadOfItsBytes() throws {
        let encoded = String(repeating: "iVBORw0KGgo", count: 5000)
        let text = [
            callLine(id: "toolu_1", name: "control", input: ["action": "screenshot"]),
            line([
                "type": "user", "sessionId": session, "uuid": UUID().uuidString,
                "timestamp": "2026-08-08T18:20:30.000Z",
                "message": [
                    "role": "user",
                    "content": [
                        [
                            "type": "tool_result", "tool_use_id": "toolu_1",
                            "content": [
                                [
                                    "type": "image",
                                    "source": [
                                        "type": "base64", "media_type": "image/png",
                                        "data": encoded,
                                    ],
                                ]
                            ],
                        ]
                    ],
                ],
            ]),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first)
        let outcome = try #require(transcript.toolActivities.first?.outcome)

        #expect(outcome == "[image omitted: image/png, 55000 encoded bytes]")
        #expect(outcome.contains("iVBORw0KGgo") == false)
    }
}

@Suite("Knowledge carries the digest of what it came from")
struct ClassifiedKnowledgeSourceTests {
    @Test("a classified entry reports the digest of the artifact it read")
    func aClassifiedEntryReportsTheDigestOfTheArtifactItRead() async throws {
        let workspace = try WorkspaceFixture.make([
            "docs/superpowers/plans/00-indice.md": "Plan index for Anchor"
        ])
        let provider = SuperpowersArtifactProvider(workspaceURL: workspace)
        let discovered = try #require(
            try await provider.discoverArtifacts(forProject: ProjectID()).first)
        let content = try #require(
            try await WorkspaceFileContentReader().readContent(
                ofArtifactNamed: discovered.artifact.name, inWorkspaceAt: workspace))

        let entries = try await provider.classifyKnowledgeEntries(
            in: discovered, content: content)

        #expect(entries.first?.sourceContentHash == discovered.contentHash)
        #expect(entries.first?.sourceContentHash == ContentHash.digest(of: content))
    }
}
