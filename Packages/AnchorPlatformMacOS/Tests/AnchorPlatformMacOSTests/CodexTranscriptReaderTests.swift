import AnchorDomain
import AnchorPlatformMacOS
import Foundation
import Testing

@Suite("Reading a Codex rollout")
struct CodexTranscriptReaderTests {
    private let reader = CodexTranscriptReader()
    private let projectID = ProjectID()
    private let sessionID = "019ff304-ca04-79a0-816a-267f4b5a1f85"
    private let workspace = "/Users/kid/bu-country/bu-payment"

    private func line(_ fields: [String: Any]) -> String {
        String(
            decoding: try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
            as: UTF8.self
        )
    }

    private func metaLine(threadSource: String) -> String {
        line([
            "type": "session_meta", "timestamp": "2026-08-12T00:50:05.000Z",
            "payload": [
                "session_id": sessionID, "cwd": workspace, "thread_source": threadSource,
            ],
        ])
    }

    private func messageLine(
        role: String, identifier: String, at timestamp: String, blocks: [[String: Any]]
    ) -> String {
        line([
            "type": "response_item", "timestamp": timestamp,
            "payload": ["type": "message", "role": role, "id": identifier, "content": blocks],
        ])
    }

    private func rollout(threadSource: String = "user", extra: [String] = []) -> String {
        ([metaLine(threadSource: threadSource)] + extra).joined(separator: "\n")
    }

    @Test("a rollout started by a person is read")
    func aRolloutStartedByAPersonIsRead() throws {
        let text = rollout(extra: [
            messageLine(
                role: "user", identifier: "msg_1", at: "2026-08-12T00:50:06.000Z",
                blocks: [["type": "input_text", "text": "build it"]])
        ])

        let transcript = try #require(
            reader.transcript(inLineDelimitedJSON: text, forProject: projectID))

        #expect(transcript.session.provider == .codex)
        #expect(transcript.messages.map(\.content) == ["build it"])
    }

    @Test("a rollout spawned by another agent is not read")
    func aRolloutSpawnedByAnotherAgentIsNotRead() {
        let text = rollout(
            threadSource: "subagent",
            extra: [
                messageLine(
                    role: "user", identifier: "msg_1", at: "2026-08-12T00:50:06.000Z",
                    blocks: [["type": "input_text", "text": "assess this permission request"]])
            ]
        )

        #expect(reader.transcript(inLineDelimitedJSON: text, forProject: projectID) == nil)
    }

    @Test("instructions given to the model are not conversation")
    func instructionsGivenToTheModelAreNotConversation() throws {
        let text = rollout(extra: [
            messageLine(
                role: "developer", identifier: "msg_0", at: "2026-08-12T00:50:05.500Z",
                blocks: [["type": "input_text", "text": "<permissions instructions>"]]),
            messageLine(
                role: "assistant", identifier: "msg_1", at: "2026-08-12T00:50:07.000Z",
                blocks: [["type": "output_text", "text": "done"]]),
        ])

        let transcript = try #require(
            reader.transcript(inLineDelimitedJSON: text, forProject: projectID))

        #expect(transcript.messages.map(\.role) == [.assistant])
    }

    @Test("the interface event stream is not read as conversation")
    func theInterfaceEventStreamIsNotReadAsConversation() throws {
        let text = rollout(extra: [
            line([
                "type": "event_msg", "timestamp": "2026-08-12T00:50:06.000Z",
                "payload": ["type": "agent_reasoning", "message": "weighing options"],
            ]),
            messageLine(
                role: "user", identifier: "msg_1", at: "2026-08-12T00:50:07.000Z",
                blocks: [["type": "input_text", "text": "only this"]]),
        ])

        let transcript = try #require(
            reader.transcript(inLineDelimitedJSON: text, forProject: projectID))

        #expect(transcript.messages.map(\.content) == ["only this"])
    }

    @Test("the working directory says which project the session belongs to")
    func theWorkingDirectorySaysWhichProjectTheSessionBelongsTo() throws {
        let origin = try #require(reader.origin(inLineDelimitedJSON: rollout()))

        #expect(origin.workingDirectory == workspace)
        #expect(origin.startedByAPerson)
        #expect(origin.sessionID == SessionID(rawValue: sessionID))
    }

    @Test("a rollout with no session meta is not read")
    func aRolloutWithNoSessionMetaIsNotRead() {
        let text = messageLine(
            role: "user", identifier: "msg_1", at: "2026-08-12T00:50:06.000Z",
            blocks: [["type": "input_text", "text": "orphan"]])

        #expect(reader.transcript(inLineDelimitedJSON: text, forProject: projectID) == nil)
    }

    @Test("the same message keeps the same identity across reads")
    func theSameMessageKeepsTheSameIdentityAcrossReads() throws {
        let text = rollout(extra: [
            messageLine(
                role: "user", identifier: "msg_1", at: "2026-08-12T00:50:06.000Z",
                blocks: [["type": "input_text", "text": "build it"]])
        ])

        let first = reader.transcript(inLineDelimitedJSON: text, forProject: projectID)
        let second = reader.transcript(inLineDelimitedJSON: text, forProject: projectID)

        #expect(first?.messages.map(\.id) == second?.messages.map(\.id))
    }

    @Test("a secret pasted into a Codex message never reaches the transcript")
    func aSecretPastedIntoACodexMessageNeverReachesTheTranscript() throws {
        let text = rollout(extra: [
            messageLine(
                role: "user", identifier: "msg_1", at: "2026-08-12T00:50:06.000Z",
                blocks: [
                    [
                        "type": "input_text",
                        "text": "use postgresql://appuser:hunter2secret@db/payments",
                    ]
                ])
        ])

        let transcript = try #require(
            reader.transcript(inLineDelimitedJSON: text, forProject: projectID))

        #expect(transcript.messages.first?.content.contains("hunter2secret") == false)
    }
}

@Suite("Tool activity and sub-agents in a Codex rollout")
struct CodexToolActivityTests {
    private let reader = CodexTranscriptReader()
    private let projectID = ProjectID()
    private let session = "019ff304-ca04-79a0-816a-267f4b5a1f85"
    private let parent = "019f81ab-0169-7500-b5ae-c20afa647a92"

    private func line(_ fields: [String: Any]) -> String {
        String(
            decoding: try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
            as: UTF8.self
        )
    }

    private func metaLine(threadSource: String, withParent: Bool = false) -> String {
        var payload: [String: Any] = [
            "session_id": session, "cwd": "/Users/kid/bu-country/bu-payment",
            "thread_source": threadSource,
        ]
        if withParent { payload["parent_thread_id"] = parent }

        return line([
            "type": "session_meta", "timestamp": "2026-08-12T00:50:05.000Z", "payload": payload,
        ])
    }

    private func callLine(callIdentifier: String, name: String, arguments: String) -> String {
        line([
            "type": "response_item", "timestamp": "2026-08-12T00:50:06.000Z",
            "payload": [
                "type": "function_call", "call_id": callIdentifier, "name": name,
                "arguments": arguments,
            ],
        ])
    }

    private func outputLine(callIdentifier: String, output: String) -> String {
        line([
            "type": "response_item", "timestamp": "2026-08-12T00:50:07.000Z",
            "payload": [
                "type": "function_call_output", "call_id": callIdentifier, "output": output,
            ],
        ])
    }

    @Test("a call and its output become one entry")
    func aCallAndItsOutputBecomeOneEntry() throws {
        let text = [
            metaLine(threadSource: "user"),
            callLine(callIdentifier: "call_1", name: "exec_command", arguments: "{\"cmd\":\"ls\"}"),
            outputLine(callIdentifier: "call_1", output: "Package.swift"),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcript(inLineDelimitedJSON: text, forProject: projectID))
        let activity = try #require(transcript.toolActivities.first)

        #expect(transcript.toolActivities.count == 1)
        #expect(activity.toolName == "exec_command")
        #expect(activity.outcome == "Package.swift")
    }

    @Test("a sub-agent that did work is kept and points at the session that spawned it")
    func aSubAgentThatDidWorkIsKeptAndPointsAtTheSessionThatSpawnedIt() throws {
        let text = [
            metaLine(threadSource: "subagent", withParent: true),
            callLine(
                callIdentifier: "call_1", name: "exec_command",
                arguments: "{\"cmd\":\"swift build\"}"),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcript(inLineDelimitedJSON: text, forProject: projectID))

        #expect(transcript.session.parentSessionID == SessionID(rawValue: parent))
        #expect(transcript.toolActivities.count == 1)
    }

    @Test("a sub-agent that only assessed something is left out")
    func aSubAgentThatOnlyAssessedSomethingIsLeftOut() {
        let text = [
            metaLine(threadSource: "subagent", withParent: true),
            line([
                "type": "response_item", "timestamp": "2026-08-12T00:50:06.000Z",
                "payload": [
                    "type": "message", "role": "assistant", "id": "msg_1",
                    "content": [["type": "output_text", "text": "{\"outcome\":\"allow\"}"]],
                ],
            ]),
        ].joined(separator: "\n")

        #expect(reader.transcript(inLineDelimitedJSON: text, forProject: projectID) == nil)
    }

    @Test("reasoning is not part of the record")
    func reasoningIsNotPartOfTheRecord() throws {
        let text = [
            metaLine(threadSource: "user"),
            line([
                "type": "response_item", "timestamp": "2026-08-12T00:50:06.000Z",
                "payload": ["type": "reasoning", "id": "rs_1", "encrypted_content": "gAAAAA"],
            ]),
            line([
                "type": "response_item", "timestamp": "2026-08-12T00:50:07.000Z",
                "payload": [
                    "type": "message", "role": "assistant", "id": "msg_1",
                    "content": [["type": "output_text", "text": "done"]],
                ],
            ]),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcript(inLineDelimitedJSON: text, forProject: projectID))

        #expect(transcript.entries.count == 1)
    }

    @Test("a secret in the arguments never reaches the record")
    func aSecretInTheArgumentsNeverReachesTheRecord() throws {
        let text = [
            metaLine(threadSource: "user"),
            callLine(
                callIdentifier: "call_1", name: "exec_command",
                arguments: "{\"cmd\":\"psql postgresql://appuser:hunter2secret@db/payments\"}"),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcript(inLineDelimitedJSON: text, forProject: projectID))

        #expect(transcript.toolActivities.first?.invocation.contains("hunter2secret") == false)
    }
}
