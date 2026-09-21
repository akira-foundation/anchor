import AnchorApplication
import Foundation
import MCP
import Testing

@testable import AnchorMCPServerCore

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
    #expect(resume.structuredContent?.objectValue?["latest_session"] == nil)
    #expect(resume.structuredContent?.objectValue?["last_activity_at"] == nil)
    #expect(resume.structuredContent?.objectValue?["last_agent_provider"] == nil)
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
