import AnchorDomain
import AnchorPlatformMacOS
import AnchorProvider
import Foundation
import Testing

@Suite("Reading a Claude transcript")
struct ClaudeTranscriptReaderTests {
    private let reader = ClaudeTranscriptReader()
    private let projectID = ProjectID()
    private let firstSession = "73519afa-1fb1-40d5-8b26-beb76f968a20"
    private let secondSession = "8e8b710b-95c6-4c35-ac98-cb7512785fef"

    private func line(_ fields: [String: Any]) -> String {
        String(
            decoding: try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
            as: UTF8.self
        )
    }

    private func userLine(
        session: String, uuid: String, at timestamp: String, saying text: String
    ) -> String {
        line([
            "type": "user", "sessionId": session, "uuid": uuid, "timestamp": timestamp,
            "message": ["role": "user", "content": text],
        ])
    }

    private func assistantLine(
        session: String, uuid: String, at timestamp: String, blocks: [[String: Any]]
    ) -> String {
        line([
            "type": "assistant", "sessionId": session, "uuid": uuid, "timestamp": timestamp,
            "message": ["role": "assistant", "content": blocks],
        ])
    }

    @Test("the session is the one the records name, not the file they came from")
    func theSessionIsTheOneTheRecordsNameNotTheFileTheyCameFrom() throws {
        let text = userLine(
            session: firstSession, uuid: UUID().uuidString,
            at: "2026-08-08T18:20:24.411Z", saying: "start"
        )

        let transcripts = reader.transcripts(inLineDelimitedJSON: text, forProject: projectID)
        let expected = try #require(SessionID(rawValue: firstSession))

        #expect(transcripts.map(\.session.id) == [expected])
    }

    @Test("one file carrying two sessions produces two transcripts")
    func oneFileCarryingTwoSessionsProducesTwoTranscripts() throws {
        let text = [
            userLine(
                session: firstSession, uuid: UUID().uuidString,
                at: "2026-08-08T18:20:24.411Z", saying: "one"),
            userLine(
                session: secondSession, uuid: UUID().uuidString,
                at: "2026-08-09T10:00:00.000Z", saying: "two"),
        ].joined(separator: "\n")

        let transcripts = reader.transcripts(inLineDelimitedJSON: text, forProject: projectID)
        let expected = try [firstSession, secondSession].map {
            try #require(SessionID(rawValue: $0))
        }

        #expect(Set(transcripts.map(\.session.id)) == Set(expected))
    }

    @Test("tool traffic is not conversation")
    func toolTrafficIsNotConversation() throws {
        let text = [
            userLine(
                session: firstSession, uuid: UUID().uuidString,
                at: "2026-08-08T18:20:24.411Z", saying: "do it"),
            line([
                "type": "user", "sessionId": firstSession, "uuid": UUID().uuidString,
                "timestamp": "2026-08-08T18:20:30.000Z",
                "message": [
                    "role": "user",
                    "content": [["type": "tool_result", "content": "1000 lines of output"]],
                ],
            ]),
            assistantLine(
                session: firstSession, uuid: UUID().uuidString,
                at: "2026-08-08T18:20:40.000Z",
                blocks: [
                    ["type": "thinking", "thinking": "weighing options"],
                    ["type": "text", "text": "done"],
                    ["type": "tool_use", "name": "Bash", "input": ["command": "ls"]],
                ]
            ),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first)

        #expect(transcript.messages.map(\.content) == ["do it", "done"])
        #expect(transcript.messages.map(\.role) == [.user, .assistant])
    }

    @Test("a record that is neither user nor assistant is ignored")
    func aRecordThatIsNeitherUserNorAssistantIsIgnored() throws {
        let text = [
            line([
                "type": "queue-operation", "sessionId": firstSession,
                "timestamp": "2026-08-08T18:20:24.411Z", "content": "queued",
            ]),
            line([
                "type": "system", "sessionId": firstSession, "uuid": UUID().uuidString,
                "timestamp": "2026-08-08T18:20:25.000Z",
            ]),
            userLine(
                session: firstSession, uuid: UUID().uuidString,
                at: "2026-08-08T18:20:26.000Z", saying: "only this"),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first)

        #expect(transcript.messages.map(\.content) == ["only this"])
    }

    @Test("the session spans the first and last record it holds")
    func theSessionSpansTheFirstAndLastRecordItHolds() throws {
        let text = [
            userLine(
                session: firstSession, uuid: UUID().uuidString,
                at: "2026-08-08T18:20:24.411Z", saying: "first"),
            userLine(
                session: firstSession, uuid: UUID().uuidString,
                at: "2026-08-08T19:00:00.000Z", saying: "last"),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first)

        #expect(transcript.session.startedAt < transcript.session.updatedAt)
        #expect(transcript.session.provider == .claude)
    }

    @Test("a secret pasted into the conversation never reaches the transcript")
    func aSecretPastedIntoTheConversationNeverReachesTheTranscript() throws {
        let text = userLine(
            session: firstSession, uuid: UUID().uuidString,
            at: "2026-08-08T18:20:24.411Z",
            saying: "connect with postgresql://appuser:hunter2secret@db/anchor"
        )

        let transcript = try #require(
            reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first)

        #expect(transcript.messages.first?.content.contains("hunter2secret") == false)
    }

    @Test("a line that is not JSON does not lose the lines around it")
    func aLineThatIsNotJSONDoesNotLoseTheLinesAroundIt() throws {
        let text = [
            userLine(
                session: firstSession, uuid: UUID().uuidString,
                at: "2026-08-08T18:20:24.411Z", saying: "before"),
            "{ this line was written while the process died",
            userLine(
                session: firstSession, uuid: UUID().uuidString,
                at: "2026-08-08T18:20:30.000Z", saying: "after"),
        ].joined(separator: "\n")

        let transcript = try #require(
            reader.transcripts(inLineDelimitedJSON: text, forProject: projectID).first)

        #expect(transcript.messages.map(\.content) == ["before", "after"])
    }
}

@Suite("Artifact identity across discoveries")
struct ProviderArtifactIdentityTests {
    @Test("discovering the same file twice names the same artifact")
    func discoveringTheSameFileTwiceNamesTheSameArtifact() async throws {
        let workspace = try WorkspaceFixture.make([
            "docs/superpowers/plans/00-indice.md": "plan"
        ])
        let projectID = ProjectID()
        let provider = SuperpowersArtifactProvider(workspaceURL: workspace)

        let first = try await provider.discoverArtifacts(forProject: projectID)
        let second = try await provider.discoverArtifacts(forProject: projectID)

        #expect(first.map(\.artifact.id) == second.map(\.artifact.id))
        #expect(first.isEmpty == false)
    }
}
