import MCP
import Testing

@testable import AnchorMCPServerCore

@Test("catalog exposes exactly eight bounded read-only tools")
func catalogToolsAreBoundedAndReadOnly() {
    let catalog = AnchorMCPToolCatalog()
    #expect(
        catalog.tools.map(\.name) == [
            "context.current_project", "context.resume", "context.search",
            "context.list_artifacts", "context.get_artifact", "context.list_sessions",
            "context.get_session", "context.get_messages",
        ])
    #expect(catalog.tools.allSatisfy { $0.annotations.readOnlyHint == true })
    #expect(catalog.tools.allSatisfy { $0.annotations.destructiveHint == false })
    #expect(catalog.tools.allSatisfy { $0.annotations.openWorldHint == false })
    #expect(
        catalog.tools.allSatisfy {
            $0.inputSchema.objectValue?["additionalProperties"] == .bool(false)
        })

    let schemas = Dictionary(uniqueKeysWithValues: catalog.tools.map { ($0.name, $0.inputSchema) })
    #expect(schemas["context.current_project"]?.objectValue?["properties"] == .object([:]))
    #expect(schemas["context.resume"]?.objectValue?["properties"] == .object([:]))
    #expect(
        schemas["context.get_session"]?.objectValue?["required"] == .array([.string("session_id")]))
    #expect(schemas["context.search"]?.objectValue?["required"] == .array([.string("text")]))
    #expect(
        schemas["context.get_artifact"]?.objectValue?["required"]
            == .array([.string("artifact_id")]))
    #expect(
        schemas["context.get_messages"]?.objectValue?["required"] == .array([.string("session_id")])
    )
    #expect(maximum("limit", in: schemas["context.search"]) == 100)
    #expect(maximum("limit", in: schemas["context.list_artifacts"]) == 100)
    #expect(maximum("limit", in: schemas["context.list_sessions"]) == 100)
    #expect(maximum("limit", in: schemas["context.get_messages"]) == 200)
    #expect(maximum("byte_limit", in: schemas["context.get_artifact"]) == 65_536)
}

private func maximum(_ property: String, in schema: Value?) -> Int? {
    schema?.objectValue?["properties"]?.objectValue?[property]?.objectValue?["maximum"]?.intValue
}
