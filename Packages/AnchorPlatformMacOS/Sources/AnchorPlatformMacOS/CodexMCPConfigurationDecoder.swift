import AnchorApplication
import Foundation

enum CodexMCPConfigurationFailure: Error, Equatable {
    case malformedOutput
    case unsupportedDefinition
}

struct CodexMCPConfigurationDecoder {
    func definition(from bytes: Data) throws -> AgentMCPDefinition {
        guard bytes.count <= 65_536 else { throw CodexMCPConfigurationFailure.malformedOutput }
        let server: Server
        do { server = try JSONDecoder().decode(Server.self, from: bytes) } catch {
            throw CodexMCPConfigurationFailure.malformedOutput
        }
        guard server.transport.type == "stdio", server.enabled,
            server.transport.workingDirectory == nil,
            server.transport.environmentVariables?.isEmpty != false,
            server.enabledTools == nil, server.disabledTools?.isEmpty != false,
            server.startupTimeout == nil, server.toolTimeout == nil
        else { throw CodexMCPConfigurationFailure.unsupportedDefinition }
        guard let command = server.transport.command, !command.isEmpty else {
            throw CodexMCPConfigurationFailure.malformedOutput
        }
        return AgentMCPDefinition(
            command: command, arguments: server.transport.arguments ?? [],
            environment: server.transport.environment ?? [:])
    }

    private struct Server: Decodable {
        let enabled: Bool
        let transport: Transport
        let enabledTools: [String]?
        let disabledTools: [String]?
        let startupTimeout: Double?
        let toolTimeout: Double?

        enum CodingKeys: String, CodingKey {
            case enabled, transport
            case enabledTools = "enabled_tools"
            case disabledTools = "disabled_tools"
            case startupTimeout = "startup_timeout_sec"
            case toolTimeout = "tool_timeout_sec"
        }
    }

    private struct Transport: Decodable {
        let type: String
        let command: String?
        let arguments: [String]?
        let environment: [String: String]?
        let environmentVariables: [String]?
        let workingDirectory: String?

        enum CodingKeys: String, CodingKey {
            case type, command
            case arguments = "args"
            case environment = "env"
            case environmentVariables = "env_vars"
            case workingDirectory = "cwd"
        }
    }
}
