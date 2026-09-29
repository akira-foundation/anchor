import MCP

public struct AnchorMCPToolCatalog: Sendable {
    public let tools: [Tool]

    public init() {
        let readOnly = Tool.Annotations(
            readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        tools = [
            Tool(
                name: "context.current_project", description: "Read the authorized project.",
                inputSchema: Self.schema([:]), annotations: readOnly),
            Tool(
                name: "context.resume", description: "Read a brief project resume.",
                inputSchema: Self.schema([:]), annotations: readOnly),
            Tool(
                name: "context.search", description: "Search indexed project context.",
                inputSchema: Self.schema(
                    [
                        "text": Self.string(minimumLength: 1), "limit": Self.integer(maximum: 100),
                        "cursor": Self.string(minimumLength: 1),
                    ], required: ["text"]), annotations: readOnly),
            Tool(
                name: "context.list_artifacts", description: "List artifact metadata.",
                inputSchema: Self.schema(
                    Self.pageProperties(maximum: 100).merging([
                        "provider": Self.provider
                    ]) { _, replacement in replacement }), annotations: readOnly),
            Tool(
                name: "context.get_artifact", description: "Read a bounded artifact text chunk.",
                inputSchema: Self.schema(
                    [
                        "artifact_id": Self.string(minimumLength: 1),
                        "revision_id": Self.string(minimumLength: 1),
                        "content_cursor": Self.string(minimumLength: 1),
                        "byte_limit": Self.integer(minimum: 4, maximum: 65_536),
                    ], required: ["artifact_id"]), annotations: readOnly),
            Tool(
                name: "context.list_sessions", description: "List session metadata.",
                inputSchema: Self.schema(
                    Self.pageProperties(maximum: 100).merging([
                        "provider": Self.provider
                    ]) { _, replacement in replacement }), annotations: readOnly),
            Tool(
                name: "context.get_session", description: "Read session metadata and counts.",
                inputSchema: Self.schema(
                    [
                        "session_id": Self.string(minimumLength: 1)
                    ], required: ["session_id"]), annotations: readOnly),
            Tool(
                name: "context.get_messages", description: "List canonical conversation entries.",
                inputSchema: Self.schema(
                    Self.pageProperties(maximum: 200).merging([
                        "session_id": Self.string(minimumLength: 1)
                    ]) { _, replacement in replacement }, required: ["session_id"]),
                annotations: readOnly),
            Tool(
                name: "context.list_knowledge", description: "List compact current knowledge.",
                inputSchema: Self.schema(
                    Self.pageProperties(maximum: 100).merging([
                        "kind": Self.enumerated([
                            "summary", "decision", "todo", "question", "risk", "architecture",
                        ]),
                        "origin": Self.enumerated(["classified", "marked", "inferred"]),
                    ]) { _, replacement in replacement }), annotations: readOnly),
            Tool(
                name: "context.get_knowledge", description: "Read one complete knowledge entry.",
                inputSchema: Self.schema(
                    ["knowledge_entry_id": Self.string(minimumLength: 1)],
                    required: ["knowledge_entry_id"]), annotations: readOnly),
        ]
    }

    private static func schema(_ properties: [String: Value], required: [String] = []) -> Value {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(Value.string)),
            "additionalProperties": .bool(false),
        ])
    }

    private static func pageProperties(maximum: Int) -> [String: Value] {
        ["limit": integer(maximum: maximum), "cursor": string(minimumLength: 1)]
    }

    private static func string(minimumLength: Int) -> Value {
        .object(["type": .string("string"), "minLength": .int(minimumLength)])
    }

    private static func integer(minimum: Int = 1, maximum: Int) -> Value {
        .object([
            "type": .string("integer"), "minimum": .int(minimum), "maximum": .int(maximum),
        ])
    }

    private static let provider: Value = .object([
        "type": .string("string"),
        "enum": .array(["claude", "codex", "superpowers", "graphify"].map(Value.string)),
    ])

    private static func enumerated(_ options: [String]) -> Value {
        .object([
            "type": .string("string"), "enum": .array(options.map(Value.string)),
        ])
    }
}
