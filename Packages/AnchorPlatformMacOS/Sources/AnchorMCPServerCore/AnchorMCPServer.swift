import MCP

public struct AnchorMCPServer: Sendable {
    private let server: Server
    private let catalog: AnchorMCPToolCatalog
    private let router: AnchorMCPToolRouter

    public init(actions: ContextQueryActions) {
        server = Server(
            name: "anchor", version: "0.1.0",
            capabilities: .init(tools: .init(listChanged: false)))
        catalog = AnchorMCPToolCatalog()
        router = AnchorMCPToolRouter(actions: actions)
    }

    public func start(transport: any Transport) async throws {
        let catalog = self.catalog
        let router = self.router
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: catalog.tools)
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            try await router.call(parameters)
        }
        try await server.start(transport: transport)
    }

    public func waitUntilCompleted() async {
        await server.waitUntilCompleted()
    }
}
