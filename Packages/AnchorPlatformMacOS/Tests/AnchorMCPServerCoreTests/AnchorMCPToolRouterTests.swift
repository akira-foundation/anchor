import AnchorApplication
import AnchorDomain
import Foundation
import MCP
import Testing

@testable import AnchorMCPServerCore

@Test("each tool dispatches to its matching context query")
func routerDispatchesTenQueries() async throws {
    let fixture = RouterFixture()
    let router = AnchorMCPToolRouter(actions: fixture.actions)
    let calls: [(String, [String: Value], String, String)] = [
        ("context.current_project", [:], "project_id", "project"),
        ("context.resume", [:], "project", "resume"),
        ("context.search", ["text": .string("needle")], "hits", "search"),
        ("context.list_artifacts", [:], "artifacts", "artifacts"),
        (
            "context.get_artifact", ["artifact_id": .string(fixture.artifact.id.rawValue)], "text",
            "artifact"
        ),
        ("context.list_sessions", [:], "sessions", "sessions"),
        (
            "context.get_session", ["session_id": .string(fixture.session.id.rawValue)],
            "message_count", "session"
        ),
        (
            "context.get_messages", ["session_id": .string(fixture.session.id.rawValue)], "entries",
            "messages"
        ),
        ("context.list_knowledge", [:], "entries", "knowledge-list"),
        (
            "context.get_knowledge",
            ["knowledge_entry_id": .string(fixture.knowledgeEntry.id.rawValue)],
            "summary", "knowledge-detail"
        ),
    ]
    for (name, arguments, expectedKey, expectedOperation) in calls {
        let before = await fixture.operations
        let response = try await router.call(.init(name: name, arguments: arguments))
        #expect(response.isError == false)
        #expect(response.structuredContent?.objectValue?[expectedKey] != nil)
        let after = await fixture.operations
        let newOperations = Array(after.dropFirst(before.count))
        #expect(newOperations.last == expectedOperation)
        #expect(
            newOperations.filter { $0 != "project" }
                == (expectedOperation == "project" ? [] : [expectedOperation]))
    }
}

@Test("router rejects undocumented arguments and unknown tools")
func routerRejectsMalformedCalls() async throws {
    let router = AnchorMCPToolRouter(actions: RouterFixture().actions)
    for parameters in [
        CallTool.Parameters(name: "context.resume", arguments: ["surprise": .bool(true)]),
        CallTool.Parameters(name: "context.unknown"),
        CallTool.Parameters(name: "context.search", arguments: ["text": .string(" ")]),
        CallTool.Parameters(
            name: "context.search", arguments: ["text": .string("x"), "limit": .int(101)]),
        CallTool.Parameters(name: "context.list_knowledge", arguments: ["kind": .string("other")]),
        CallTool.Parameters(
            name: "context.list_knowledge", arguments: ["origin": .string("other")]),
        CallTool.Parameters(name: "context.list_knowledge", arguments: ["limit": .bool(true)]),
        CallTool.Parameters(name: "context.list_knowledge", arguments: ["limit": .int(101)]),
        CallTool.Parameters(name: "context.list_knowledge", arguments: ["extra": .int(1)]),
        CallTool.Parameters(name: "context.get_knowledge", arguments: [:]),
        CallTool.Parameters(
            name: "context.get_knowledge", arguments: ["knowledge_entry_id": .string(" ")]),
        CallTool.Parameters(
            name: "context.get_knowledge", arguments: ["knowledge_entry_id": .string("")]),
        CallTool.Parameters(
            name: "context.get_knowledge",
            arguments: ["knowledge_entry_id": .string("not-an-identifier")]),
        CallTool.Parameters(
            name: "context.get_knowledge",
            arguments: ["knowledge_entry_id": .string(UUID().uuidString), "extra": .bool(true)]),
    ] {
        do {
            _ = try await router.call(parameters)
            Issue.record("Expected invalidParams for \(parameters.name)")
        } catch MCPError.invalidParams(_) {
        } catch {
            Issue.record("Expected invalidParams for \(parameters.name), received \(error)")
        }
    }
}

@Test("knowledge filters are forwarded as typed values and cursors map to typed failures")
func routerForwardsKnowledgeFiltersAndMapsCursorFailure() async throws {
    let fixture = RouterFixture()
    let router = AnchorMCPToolRouter(actions: fixture.actions)
    let response = try await router.call(
        .init(
            name: "context.list_knowledge",
            arguments: [
                "kind": .string("decision"), "origin": .string("marked"), "limit": .int(1),
            ]))
    #expect(response.isError == false)
    #expect(await fixture.requestedKnowledgeKind == .decision)
    #expect(await fixture.requestedKnowledgeOrigin == .marked)
    #expect(await fixture.requestedKnowledgeLimit == 1)
    let cursorFailure = try await router.call(
        .init(
            name: "context.list_knowledge", arguments: ["cursor": .string("search-cursor")]))
    #expect(cursorFailure.isError == true)
    #expect(cursorFailure.structuredContent?.objectValue?["code"] == .string("invalid_cursor"))
    let missing = try await router.call(
        .init(
            name: "context.get_knowledge",
            arguments: ["knowledge_entry_id": .string(KnowledgeEntryID().rawValue)]))
    #expect(missing.structuredContent?.objectValue?["code"] == .string("entity_not_found"))
}

@Test("knowledge tools preserve typed failure codes")
func routerMapsKnowledgeFailures() async throws {
    for (failure, code) in [
        (ContextQueryFailure.workspaceNotAuthorized, "workspace_not_authorized"),
        (.contextUnavailable, "context_unavailable"),
        (.readFailed, "read_failed"),
    ] {
        let fixture = RouterFixture(failure: failure)
        for (name, arguments) in [
            ("context.list_knowledge", [String: Value]()),
            (
                "context.get_knowledge",
                ["knowledge_entry_id": .string(fixture.knowledgeEntry.id.rawValue)]
            ),
        ] {
            let response = try await AnchorMCPToolRouter(actions: fixture.actions).call(
                .init(name: name, arguments: arguments))
            #expect(response.isError == true)
            #expect(response.structuredContent?.objectValue?["code"] == .string(code))
        }
    }
}

@Test("legacy eight-action composition reports unavailable knowledge")
func legacyActionBundleMapsKnowledgeUnavailable() async throws {
    let fixture = RouterFixture()
    let suppliedActions = fixture.actions
    let legacyActions = ContextQueryActions(
        currentProject: suppliedActions.currentProject,
        resume: suppliedActions.resume,
        search: suppliedActions.search,
        listArtifacts: suppliedActions.listArtifacts,
        readArtifact: suppliedActions.readArtifact,
        listSessions: suppliedActions.listSessions,
        readSession: suppliedActions.readSession,
        readMessages: suppliedActions.readMessages)
    let router = AnchorMCPToolRouter(actions: legacyActions)
    for (name, arguments) in [
        ("context.list_knowledge", [String: Value]()),
        (
            "context.get_knowledge",
            ["knowledge_entry_id": .string(fixture.knowledgeEntry.id.rawValue)]
        ),
    ] {
        let response = try await router.call(.init(name: name, arguments: arguments))
        #expect(response.isError == true)
        #expect(response.structuredContent?.objectValue?["code"] == .string("context_unavailable"))
    }
}

@Test("domain failures have stable codes without leaking internal details")
func routerMapsFailuresSafely() async throws {
    let cases: [(ContextQueryFailure, String)] = [
        (.workspaceNotConfigured, "workspace_not_configured"),
        (.workspaceNotAuthorized, "workspace_not_authorized"),
        (.contextUnavailable, "context_unavailable"),
        (.entityNotFound, "entity_not_found"),
        (.invalidCursor, "invalid_cursor"),
        (.contentIsNotText, "content_not_text"),
        (.readFailed, "read_failed"),
    ]
    for (failure, code) in cases {
        let fixture = RouterFixture(failure: failure)
        let response = try await AnchorMCPToolRouter(actions: fixture.actions).call(
            .init(name: "context.current_project"))
        #expect(response.isError == true)
        #expect(response.structuredContent?.objectValue?["code"] == .string(code))
        #expect(response.structuredContent?.objectValue?["message"]?.stringValue != nil)
        #expect(!String(describing: response).contains("fixture-secret"))
    }
}

@Test("in-memory client initializes, lists tools and calls the server")
func serverServesToolsOverInMemoryTransport() async throws {
    let fixture = RouterFixture()
    let server = AnchorMCPServer(actions: fixture.actions)
    let transports = await InMemoryTransport.createConnectedPair()
    try await server.start(transport: transports.server)
    let client = Client(name: "anchor-test", version: "1.0.0")
    let initialization = try await client.connect(transport: transports.client)
    #expect(initialization.serverInfo.name == "anchor")
    let listed = try await client.listTools()
    #expect(listed.tools.count == 10)
    let call = try await client.callTool(name: "context.current_project")
    #expect(call.isError == false)
    #expect(!call.content.isEmpty)
    await client.disconnect()
    await server.waitUntilCompleted()
}
