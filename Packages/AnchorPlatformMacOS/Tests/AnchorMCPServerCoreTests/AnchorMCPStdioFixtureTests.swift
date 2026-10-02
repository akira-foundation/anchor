import AnchorApplication
import AnchorDomain
import AnchorPlatformMacOS
import Foundation
import Testing

@Suite("MCP stdio read-model fixture")
struct AnchorMCPStdioFixtureTests {
    @Test("the persisted fixture serves progressive knowledge without an encryption key")
    func fixtureServesProgressiveKnowledgeAndRefusesEncryptedContent() async throws {
        let fixture = try await MCPStdioFixture.create()
        defer { fixture.removeOwnedDirectory() }
        let reader = try await fixture.reader()
        let project = try await reader.currentProject.perform(ProjectContextRequest())
        #expect(project.displayName == "anchor-stdio-fixture")
        #expect(
            WorkspacePath.comparable(project.workspaceURL)
                == WorkspacePath.comparable(fixture.workspaceURL))
        let artifacts = try await reader.listArtifacts.perform(
            try #require(ListProjectArtifactsRequest(limit: 1)))
        #expect(artifacts.records.count == 1)
        #expect(artifacts.nextCursor != nil)
        let artifact = try #require(artifacts.records.first)
        #expect(artifact.artifact.name == "stdio-latest-note.md")
        let sessions = try await reader.listSessions.perform(
            try #require(ListProjectSessionsRequest(limit: 1)))
        #expect(sessions.records.count == 1)
        #expect(sessions.nextCursor != nil)
        let session = try #require(sessions.records.first)
        #expect(session.session.provider == .codex)
        let metadata = try await reader.readSession.perform(
            ReadProjectSessionRequest(sessionID: session.session.id))
        #expect(metadata.messageCount == 2)
        #expect(metadata.toolActivityCount == 1)
        let entries = try await reader.readMessages.perform(
            try #require(ReadSessionMessagesRequest(sessionID: session.session.id)))
        try #require(entries.records.count == 3)
        guard case .message(let message) = entries.records[0],
            case .toolActivity(let activity) = entries.records[2]
        else {
            Issue.record("Fixture must contain a message followed by tool activity")
            return
        }
        #expect(message.role == .user)
        #expect(message.content == "stdio checkpoint ready API_KEY=[redacted:assigned-secret]")
        #expect(activity.toolName == "read")
        #expect(activity.invocation == "inspect stdio-latest-note.md")
        let search = try await reader.search.perform(
            try #require(SearchProjectContextRequest(text: "checkpoint", limit: 1)))
        #expect(search.records.count == 1)
        #expect(search.nextCursor == nil)
        #expect(search.records.first?.sessionID == session.session.id)
        let resume = try await reader.resume.perform(ProjectContextRequest())
        #expect(resume.project.projectID == project.projectID)
        #expect(
            resume.recentSession?.session.id
                == SessionID.derived(fromSeed: "stdio-recent-session"))
        #expect(resume.recentSession?.session.provider == .codex)
        #expect(resume.recentSession?.messageCount == 2)
        #expect(resume.recentSession?.toolActivityCount == 1)
        #expect(
            resume.currentPlan?.artifact.id
                == ArtifactID.derived(fromSeed: "stdio-current-plan"))
        #expect(
            resume.latestBrainstorm?.artifact.id
                == ArtifactID.derived(fromSeed: "stdio-brainstorm"))
        #expect(
            resume.relevantGraphs.map(\.artifact.id)
                == (0..<3).map { ArtifactID.derived(fromSeed: "stdio-graph-\($0)") })
        #expect(resume.recentDecisions.count == 5)
        #expect(resume.openTodos.count == 5)
        #expect(resume.openQuestions.count == 5)
        #expect(resume.hasMoreDecisions)
        #expect(resume.hasMoreTodos)
        #expect(resume.hasMoreQuestions)
        #expect(
            resume.recentDecisions.map(\.id)
                == (0..<5).map { KnowledgeEntryID.derived(fromSeed: "stdio-decision-\($0)") })
        #expect(
            resume.openTodos.map(\.id)
                == (0..<5).map { KnowledgeEntryID.derived(fromSeed: "stdio-todo-\($0)") })
        #expect(
            resume.openQuestions.map(\.id)
                == (0..<5).map { KnowledgeEntryID.derived(fromSeed: "stdio-question-\($0)") })
        #expect(resume.recentDecisions.first?.summary.utf8.count == 512)
        #expect(resume.recentDecisions.first?.summaryIsTruncated == true)
        let decision = try #require(resume.recentDecisions.first)
        let knowledgePage = try await reader.listKnowledge.perform(
            try #require(ListProjectKnowledgeRequest(kind: .decision, origin: .marked, limit: 1)))
        #expect(knowledgePage.records.count == 1)
        #expect(knowledgePage.nextCursor != nil)
        let compactDecision = try #require(knowledgePage.records.first)
        #expect(compactDecision.id == decision.id)
        #expect(compactDecision.kind == .decision)
        #expect(compactDecision.origin == .marked)
        #expect(compactDecision.summary.utf8.count == 512)
        #expect(compactDecision.summary == decision.summary)
        #expect(compactDecision.summaryIsTruncated)
        let completeDecision = try await reader.readKnowledge.perform(
            ReadProjectKnowledgeRequest(knowledgeEntryID: decision.id))
        #expect(completeDecision.id == decision.id)
        #expect(completeDecision.summaryText == String(repeating: "d", count: 600))
        #expect(completeDecision.summaryText.utf8.count == 600)
        #expect(
            completeDecision.sourceContentHash
                == ContentHash.digest(of: Data("stdio-decision-0".utf8)))
        #expect(
            completeDecision.supportingMessageIDs == [
                MessageID.derived(fromSeed: "stdio-response"),
                MessageID.derived(fromSeed: "stdio-message"),
            ])
        for hiddenSeed in ["stdio-superseded", "stdio-foreign-decision"] {
            await #expect(throws: ContextQueryFailure.entityNotFound) {
                try await reader.readKnowledge.perform(
                    ReadProjectKnowledgeRequest(
                        knowledgeEntryID: KnowledgeEntryID.derived(fromSeed: hiddenSeed)))
            }
        }
        #expect(resume.lastPresence?.deviceID == DeviceID.derived(fromSeed: "stdio-latest-device"))
        #expect(resume.lastActivityAt == Date(timeIntervalSince1970: 110))
        #expect(resume.lastAgentProvider == .codex)
        #expect(await fixture.keyLoads.count == 0)
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await reader.readArtifact.perform(
                try #require(ReadProjectArtifactRequest(artifactID: artifact.artifact.id)))
        }
        #expect(await fixture.keyLoads.count == 1)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.supportURL.appending(path: "storage").path()))
    }
}
