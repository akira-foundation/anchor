import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct CodexMCPConfigurationDecoderTests {
    @Test("Codex JSON preserves exact stdio command, argument tokens and environment")
    func exactDefinition() throws {
        let bytes = Data(
            #"{"name":"anchor","enabled":true,"disabled_reason":null,"transport":{"type":"stdio","command":"/Applications/Anchor é.app/server","args":["--workspace","/space ' café"],"env":{"TOKEN":"private"},"env_vars":[],"cwd":null},"enabled_tools":null,"disabled_tools":null,"startup_timeout_sec":null,"tool_timeout_sec":null,"diagnostic":"ignored"}"#
                .utf8)
        #expect(
            try CodexMCPConfigurationDecoder().definition(from: bytes)
                == AgentMCPDefinition(
                    command: "/Applications/Anchor é.app/server",
                    arguments: ["--workspace", "/space ' café"],
                    environment: ["TOKEN": "private"]))
    }

    @Test("null optional stdio collections decode as empty")
    func nullCollections() throws {
        let bytes = Data(
            #"{"name":"anchor","enabled":true,"transport":{"type":"stdio","command":"/server","args":[],"env":null,"env_vars":[],"cwd":null}}"#
                .utf8)
        #expect(
            try CodexMCPConfigurationDecoder().definition(from: bytes)
                == AgentMCPDefinition(
                    command: "/server", arguments: [], environment: [:]))
    }

    @Test(
        "remote and customized stdio entries cannot establish Anchor ownership",
        arguments: [
            #"{"type":"streamable_http","url":"https://example.test"}"#,
            #"{"type":"stdio","command":"/server","cwd":"/custom"}"#,
            #"{"type":"stdio","command":"/server","env_vars":["TOKEN"]}"#,
        ])
    func unsupportedTransport(transport: String) {
        let bytes = Data("{\"name\":\"anchor\",\"enabled\":true,\"transport\":\(transport)}".utf8)
        #expect(throws: CodexMCPConfigurationFailure.unsupportedDefinition) {
            try CodexMCPConfigurationDecoder().definition(from: bytes)
        }
    }

    @Test(
        "disabled or filtered servers are preserved",
        arguments: [
            #""enabled":false"#, #""enabled":true,"enabled_tools":["search"]"#,
            #""enabled":true,"disabled_tools":["search"]"#,
            #""enabled":true,"startup_timeout_sec":9"#,
            #""enabled":true,"tool_timeout_sec":9"#,
        ])
    func unsupportedServerOptions(options: String) {
        let bytes = Data(
            "{\"name\":\"anchor\",\(options),\"transport\":{\"type\":\"stdio\",\"command\":\"/server\"}}"
                .utf8)
        #expect(throws: CodexMCPConfigurationFailure.unsupportedDefinition) {
            try CodexMCPConfigurationDecoder().definition(from: bytes)
        }
    }

    @Test(
        "malformed or incorrectly typed inspection output is a bounded safe failure",
        arguments: [
            "secret invalid JSON", "[]", "{}",
            #"{"name":"anchor","enabled":true,"transport":{"type":"stdio"}}"#,
            #"{"name":"anchor","enabled":true,"transport":{"type":"stdio","command":1}}"#,
            #"{"name":"anchor","enabled":true,"transport":{"type":"stdio","command":""}}"#,
            #"{"name":"anchor","enabled":true,"transport":{"type":"stdio","command":"/server","args":{}}}"#,
            #"{"name":"anchor","enabled":true,"transport":{"type":"stdio","command":"/server","env":{"TOKEN":1}}}"#,
            #"{"name":"anchor","enabled":"true","transport":{"type":"stdio","command":"/server"}}"#,
        ])
    func malformedOutput(json: String) {
        #expect(throws: CodexMCPConfigurationFailure.malformedOutput) {
            try CodexMCPConfigurationDecoder().definition(from: Data(json.utf8))
        }
    }

    @Test("oversized inspection output is rejected before decoding")
    func oversizedOutput() {
        #expect(throws: CodexMCPConfigurationFailure.malformedOutput) {
            try CodexMCPConfigurationDecoder().definition(
                from: Data(String(repeating: "x", count: 65_537).utf8))
        }
    }
}
