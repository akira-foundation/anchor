import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct ClaudeUserMCPConfigurationReaderTests {
    @Test("absent configuration and absent server are not registrations")
    func absentServer() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configurationURL = directory.appendingPathComponent(".claude.json")
        let reader = ClaudeUserMCPConfigurationReader(configurationURL: configurationURL)
        #expect(try reader.definition(named: "anchor") == nil)
        try Data(#"{"mcpServers":{"other":{"command":"other"}},"secret":"untouched"}"#.utf8)
            .write(to: configurationURL)
        #expect(try reader.definition(named: "anchor") == nil)
    }

    @Test("stdio inspection preserves exact command arguments environment and unrelated bytes")
    func exactDefinition() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configurationURL = directory.appendingPathComponent(".claude.json")
        let bytes = Data(
            #"{"mcpServers":{"anchor":{"type":"stdio","command":"/App é/Anchor","args":["--workspace","/space ' folder"],"env":{"TOKEN":"private"}}},"unknown":{"keep":true}}"#
                .utf8)
        try bytes.write(to: configurationURL)
        let definition = try ClaudeUserMCPConfigurationReader(configurationURL: configurationURL)
            .definition(named: "anchor")
        #expect(
            definition
                == AgentMCPDefinition(
                    command: "/App é/Anchor", arguments: ["--workspace", "/space ' folder"],
                    environment: ["TOKEN": "private"]))
        #expect(try Data(contentsOf: configurationURL) == bytes)
    }

    @Test("missing optional stdio fields normalize to empty collections")
    func optionalFields() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configurationURL = directory.appendingPathComponent(".claude.json")
        try Data(#"{"mcpServers":{"anchor":{"command":"/server"}}}"#.utf8).write(
            to: configurationURL)
        #expect(
            try ClaudeUserMCPConfigurationReader(configurationURL: configurationURL).definition(
                named: "anchor")
                == AgentMCPDefinition(command: "/server", arguments: [], environment: [:]))
    }

    @Test(
        "malformed and unrepresentable entries never look absent",
        arguments: [
            "{", "[]", #"{"mcpServers":[]}"#,
            #"{"mcpServers":{"anchor":{"type":"http","url":"https://example.test"}}}"#,
            #"{"mcpServers":{"anchor":{"command":"/server","extra":true}}}"#,
            #"{"mcpServers":{"anchor":{"command":"/server","args":null}}}"#,
        ])
    func invalidEntries(bytes: String) throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configurationURL = directory.appendingPathComponent(".claude.json")
        try Data(bytes.utf8).write(to: configurationURL)
        #expect(throws: (any Error).self) {
            try ClaudeUserMCPConfigurationReader(configurationURL: configurationURL).definition(
                named: "anchor")
        }
    }

    @Test("local and project definitions shadow user scope without modification")
    func shadowingScopes() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configurationURL = directory.appendingPathComponent(".claude.json")
        let userBytes = try JSONSerialization.data(withJSONObject: [
            "projects": [directory.path: ["mcpServers": ["anchor": ["type": "http"]]]]
        ])
        let projectBytes = Data(#"{"mcpServers":{"anchor":{"command":"/custom"}}}"#.utf8)
        try userBytes.write(to: configurationURL)
        try projectBytes.write(to: directory.appendingPathComponent(".mcp.json"))
        let reader = ClaudeUserMCPConfigurationReader(configurationURL: configurationURL)
        #expect(
            try reader.shadowingScopes(named: "anchor", workingDirectoryURL: directory) == [
                .local, .project,
            ])
        #expect(try reader.shadowingScopes(named: "other", workingDirectoryURL: directory).isEmpty)
        #expect(try Data(contentsOf: configurationURL) == userBytes)
        #expect(try Data(contentsOf: directory.appendingPathComponent(".mcp.json")) == projectBytes)
    }

    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
