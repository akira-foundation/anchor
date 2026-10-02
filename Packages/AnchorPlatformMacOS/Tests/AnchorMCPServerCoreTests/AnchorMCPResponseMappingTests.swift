import AnchorApplication
import Foundation
import MCP
import Testing

@testable import AnchorMCPServerCore

@Test("resume maps the complete compact persisted context")
func routerMapsCompleteResume() async throws {
    let fixture = RouterFixture()
    let response = try await AnchorMCPToolRouter(actions: fixture.actions).call(
        .init(name: "context.resume"))
    let fields = try #require(response.structuredContent?.objectValue)
    #expect(
        Set(fields.keys) == [
            "project", "last_activity_at", "last_device", "last_agent_provider",
            "recent_session", "current_plan", "latest_brainstorm", "relevant_graphs",
            "recent_decisions", "open_todos", "open_questions",
        ])
    #expect(fields["last_activity_at"] == .string(Date(timeIntervalSince1970: 40).ISO8601Format()))
    #expect(fields["last_agent_provider"] == .string("codex"))
    let device = try #require(fields["last_device"]?.objectValue)
    #expect(device["device_id"] == .string(fixture.populatedResume.lastPresence!.deviceID.rawValue))
    #expect(device["last_seen_at"] == .string(Date(timeIntervalSince1970: 30).ISO8601Format()))
    let session = try #require(fields["recent_session"]?.objectValue)
    #expect(session["session_id"] == .string(fixture.session.id.rawValue))
    #expect(session["message_count"] == .int(7))
    #expect(session["tool_activity_count"] == .int(3))

    let plan = try #require(fields["current_plan"]?.objectValue)
    #expect(
        plan["artifact_id"]
            == .string(fixture.populatedResume.currentPlan!.artifact.id.rawValue))
    #expect(
        plan["revision_id"]
            == .string(fixture.populatedResume.currentPlan!.latestRevision!.id.rawValue))
    #expect(plan["name"] == .string("docs/superpowers/plans/current.md"))
    #expect(plan["updated_at"] == .string(Date(timeIntervalSince1970: 31).ISO8601Format()))
    #expect(
        fields["latest_brainstorm"]?.objectValue?["updated_at"]
            == .string(Date(timeIntervalSince1970: 32).ISO8601Format()))
    #expect(fields["relevant_graphs"]?.arrayValue?.count == 1)

    let decisions = try #require(fields["recent_decisions"]?.objectValue)
    #expect(decisions["has_more"] == .bool(true))
    let decision = try #require(decisions["entries"]?.arrayValue?.first?.objectValue)
    let expectedDecision = fixture.populatedResume.recentDecisions[0]
    #expect(decision["knowledge_entry_id"] == .string(expectedDecision.id.rawValue))
    #expect(decision["summary"] == .string(expectedDecision.summary))
    #expect(decision["summary_is_truncated"] == .bool(true))
    #expect(decision["origin"] == .string("marked"))
    #expect(decision["created_at"] == .string(Date(timeIntervalSince1970: 34).ISO8601Format()))
    #expect(decision["source"]?.objectValue?["kind"] == .string("artifact"))
    #expect(
        decision["source"]?.objectValue?["artifact_id"]
            == .string(fixture.populatedResume.currentPlan!.artifact.id.rawValue))

    let todos = try #require(fields["open_todos"]?.objectValue)
    let todo = try #require(todos["entries"]?.arrayValue?.first?.objectValue)
    #expect(todos["has_more"] == .bool(false))
    #expect(todo["source"]?.objectValue?["kind"] == .string("session"))
    #expect(todo["source"]?.objectValue?["session_id"] == .string(fixture.session.id.rawValue))
    #expect(todo["summary_is_truncated"] == nil)
    #expect(fields["open_questions"]?.objectValue?["has_more"] == .bool(true))
}

@Test("message entries retain their canonical kinds and text fallback is concise")
func routerMapsConversationKinds() async throws {
    let fixture = RouterFixture()
    let response = try await AnchorMCPToolRouter(actions: fixture.actions).call(
        .init(
            name: "context.get_messages",
            arguments: ["session_id": .string(fixture.session.id.rawValue)]))
    let entries = response.structuredContent?.objectValue?["entries"]?.arrayValue
    #expect(
        entries?.map { $0.objectValue?["entry_kind"] } == [
            .string("message"), .string("tool_activity"),
        ])
    #expect(entries?.first?.objectValue?["content"] == .string("fixture-secret long message"))
    #expect(entries?.first?.objectValue?["content_is_truncated"] == .bool(false))
    #expect(entries?.last?.objectValue?["outcome"] == nil)
    #expect(entries?.last?.objectValue?["invocation_is_truncated"] == .bool(false))
    #expect(entries?.last?.objectValue?["tool_name_is_truncated"] == .bool(false))
    #expect(entries?.last?.objectValue?["outcome_is_truncated"] == nil)
    #expect(response.structuredContent?.objectValue?["next_cursor"] == nil)
    #expect(!String(describing: response.content).contains("fixture-secret"))
}

@Test("optional project and session fields are omitted without evidence")
func routerOmitsUnavailableFields() async throws {
    let fixture = RouterFixture(includesSession: false)
    let router = AnchorMCPToolRouter(actions: fixture.actions)
    let project = try await router.call(.init(name: "context.current_project"))
    #expect(project.structuredContent?.objectValue?["canonical_remote"] == nil)
    #expect(project.structuredContent?.objectValue?["name_is_truncated"] == nil)
    #expect(project.structuredContent?.objectValue?["workspace_path_is_truncated"] == nil)
    #expect(project.structuredContent?.objectValue?["canonical_remote_is_truncated"] == nil)
    let resume = try await router.call(.init(name: "context.resume"))
    let resumeFields = try #require(resume.structuredContent?.objectValue)
    #expect(resumeFields["last_activity_at"] == nil)
    #expect(resumeFields["last_device"] == nil)
    #expect(resumeFields["last_agent_provider"] == nil)
    #expect(resumeFields["recent_session"] == nil)
    #expect(resumeFields["current_plan"] == nil)
    #expect(resumeFields["latest_brainstorm"] == nil)
    #expect(resumeFields["relevant_graphs"] == .array([]))
    for collectionName in ["recent_decisions", "open_todos", "open_questions"] {
        #expect(
            resumeFields[collectionName]
                == .object(["entries": .array([]), "has_more": .bool(false)]))
    }
    let artifacts = try await router.call(.init(name: "context.list_artifacts"))
    #expect(
        artifacts.structuredContent?.objectValue?["artifacts"]?.arrayValue?.first?.objectValue?[
            "name_is_truncated"] == nil)
}

@Test("message response bounds each variable body in UTF-8 bytes")
func routerBoundsConversationBodies() async throws {
    let longText = String(repeating: "é", count: 9_000)
    let fixture = RouterFixture(
        messageContent: longText, toolName: longText, invocation: longText, outcome: longText)
    let response = try await AnchorMCPToolRouter(actions: fixture.actions).call(
        .init(
            name: "context.get_messages",
            arguments: ["session_id": .string(fixture.session.id.rawValue)]))
    let entries = try #require(response.structuredContent?.objectValue?["entries"]?.arrayValue)
    let message = try #require(entries.first?.objectValue)
    let activity = try #require(entries.last?.objectValue)
    #expect(message["content_is_truncated"] == .bool(true))
    #expect(activity["invocation_is_truncated"] == .bool(true))
    #expect(activity["tool_name_is_truncated"] == .bool(true))
    #expect(activity["outcome_is_truncated"] == .bool(true))
    for emittedText in [
        message["content"]?.stringValue,
        activity["tool_name"]?.stringValue,
        activity["invocation"]?.stringValue,
        activity["outcome"]?.stringValue,
    ] {
        let boundedText = try #require(emittedText)
        #expect(boundedText.utf8.count <= 16_384)
        #expect(boundedText.hasSuffix("… [truncated]"))
        #expect(longText.hasPrefix(boundedText.dropLast("… [truncated]".count)))
    }
}

@Test("project, artifact and search text are bounded without changing identifiers")
func routerBoundsMetadataAndSearchText() async throws {
    let longText = String(repeating: "é", count: 9_000)
    let fixture = RouterFixture(
        projectName: longText, workspacePath: "/" + longText,
        canonicalRemote: "github.com/" + longText,
        artifactName: longText, searchExcerpt: longText)
    let router = AnchorMCPToolRouter(actions: fixture.actions)
    let projectResponse = try await router.call(.init(name: "context.current_project"))
    let project = try #require(projectResponse.structuredContent?.objectValue)
    #expect(project["project_id"] == .string(fixture.project.projectID.rawValue))
    for fieldName in ["name", "workspace_path", "canonical_remote"] {
        let emittedText = try #require(project[fieldName]?.stringValue)
        #expect(emittedText.utf8.count <= 16_384)
        #expect(emittedText.hasSuffix("… [truncated]"))
        #expect(project["\(fieldName)_is_truncated"] == .bool(true))
    }

    let artifactsResponse = try await router.call(.init(name: "context.list_artifacts"))
    let artifacts = try #require(
        artifactsResponse.structuredContent?.objectValue?["artifacts"]?.arrayValue)
    let artifact = try #require(artifacts.first?.objectValue)
    #expect(artifact["artifact_id"] == .string(fixture.artifact.id.rawValue))
    #expect(artifact["name"]?.stringValue?.utf8.count ?? 0 <= 16_384)
    #expect(artifact["name_is_truncated"] == .bool(true))

    let searchResponse = try await router.call(
        .init(name: "context.search", arguments: ["text": .string("needle")]))
    let hits = try #require(searchResponse.structuredContent?.objectValue?["hits"]?.arrayValue)
    let hit = try #require(hits.first?.objectValue)
    #expect(hit["session_id"] == .string(fixture.session.id.rawValue))
    #expect(hit["excerpt"]?.stringValue?.utf8.count ?? 0 <= 16_384)
    #expect(hit["excerpt_is_truncated"] == .bool(true))
}

@Test("four-byte Unicode remains complete at and across the exact byte boundary")
func routerPreservesFourByteUnicodeAtByteBoundary() async throws {
    let exactContent = String(repeating: "\u{1F600}", count: 4_096)
    let exactFixture = RouterFixture(messageContent: exactContent)
    let exactResponse = try await AnchorMCPToolRouter(actions: exactFixture.actions).call(
        .init(
            name: "context.get_messages",
            arguments: ["session_id": .string(exactFixture.session.id.rawValue)]))
    let exactMessage = try #require(
        exactResponse.structuredContent?.objectValue?["entries"]?.arrayValue?.first?.objectValue)
    #expect(exactContent.utf8.count == 16_384)
    #expect(exactMessage["content"] == .string(exactContent))
    #expect(exactMessage["content_is_truncated"] == .bool(false))

    let overlongContent = "a" + exactContent
    let overlongFixture = RouterFixture(messageContent: overlongContent)
    let overlongResponse = try await AnchorMCPToolRouter(actions: overlongFixture.actions).call(
        .init(
            name: "context.get_messages",
            arguments: ["session_id": .string(overlongFixture.session.id.rawValue)]))
    let overlongMessage = try #require(
        overlongResponse.structuredContent?.objectValue?["entries"]?.arrayValue?.first?.objectValue)
    #expect(overlongContent.utf8.count == 16_385)
    #expect(
        overlongMessage["content"]
            == .string("a" + String(repeating: "\u{1F600}", count: 4_092) + "… [truncated]"))
    #expect(overlongMessage["content_is_truncated"] == .bool(true))
}

@Test("knowledge list maps compact entries and keeps summaries out of text content")
func routerMapsCompactKnowledgePage() async throws {
    let fixture = RouterFixture()
    let response = try await AnchorMCPToolRouter(actions: fixture.actions).call(
        .init(name: "context.list_knowledge"))
    let fields = try #require(response.structuredContent?.objectValue)
    #expect(fields["next_cursor"] == .string("knowledge-next"))
    let entry = try #require(fields["entries"]?.arrayValue?.first?.objectValue)
    #expect(
        Set(entry.keys) == [
            "knowledge_entry_id", "kind", "summary", "summary_is_truncated",
            "origin", "created_at", "source",
        ])
    #expect(entry["knowledge_entry_id"] == .string(fixture.knowledgeEntry.id.rawValue))
    #expect(entry["kind"] == .string("decision"))
    #expect(entry["origin"] == .string("marked"))
    #expect(entry["created_at"] == .string(fixture.knowledgeEntry.createdAt.ISO8601Format()))
    #expect(entry["summary"]?.stringValue?.utf8.count ?? 0 <= 512)
    #expect(entry["summary_is_truncated"] == .bool(true))
    #expect(entry["source"]?.objectValue?["kind"] == .string("session"))
    #expect(entry["source"]?.objectValue?["session_id"] == .string(fixture.session.id.rawValue))
    #expect(
        response.content == [
            .text(text: "Knowledge entries available.", annotations: nil, _meta: nil)
        ])
    #expect(!String(describing: response.content).contains("fixture-secret"))
}

@Test("knowledge detail maps complete summary, source hash and ordered evidence")
func routerMapsCompleteKnowledgeEntry() async throws {
    let fixture = RouterFixture()
    let response = try await AnchorMCPToolRouter(actions: fixture.actions).call(
        .init(
            name: "context.get_knowledge",
            arguments: [
                "knowledge_entry_id": .string(fixture.knowledgeEntry.id.rawValue)
            ]))
    let fields = try #require(response.structuredContent?.objectValue)
    #expect(
        Set(fields.keys) == [
            "knowledge_entry_id", "kind", "summary", "origin", "created_at", "source",
            "source_content_hash", "supporting_message_ids",
        ])
    #expect(fields["knowledge_entry_id"] == .string(fixture.knowledgeEntry.id.rawValue))
    #expect(fields["kind"] == .string("decision"))
    #expect(fields["summary"] == .string(fixture.knowledgeEntry.summaryText))
    #expect(fields["origin"] == .string("marked"))
    #expect(fields["created_at"] == .string(fixture.knowledgeEntry.createdAt.ISO8601Format()))
    #expect(fields["source"]?.objectValue?["kind"] == .string("session"))
    #expect(fields["source"]?.objectValue?["session_id"] == .string(fixture.session.id.rawValue))
    #expect(
        fields["source_content_hash"] == .string(fixture.knowledgeEntry.sourceContentHash.rawValue))
    #expect(
        fields["supporting_message_ids"]
            == .array(
                fixture.knowledgeEntry.supportingMessageIDs.map { .string($0.rawValue) }))
    #expect(
        response.content == [
            .text(text: "Knowledge entry available.", annotations: nil, _meta: nil)
        ])
    #expect(!String(describing: response.content).contains("fixture-secret"))
    #expect(!String(describing: response.content).contains("second"))
}
