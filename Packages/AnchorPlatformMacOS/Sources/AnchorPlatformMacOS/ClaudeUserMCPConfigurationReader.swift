import AnchorApplication
import Foundation

enum ClaudeMCPConfigurationScope: Sendable {
    case local
    case project
}

enum ClaudeMCPConfigurationFailure: Error {
    case malformedConfiguration
    case unsupportedDefinition
}

struct ClaudeUserMCPConfigurationReader: Sendable {
    let configurationURL: URL

    func definition(named name: String) throws -> AgentMCPDefinition? {
        let configuration = try readDictionary(at: configurationURL)
        guard let entry = try dictionary(configuration, key: "mcpServers")[name] else { return nil }
        guard let definition = entry as? [String: Any],
            Set(definition.keys).isSubset(of: ["type", "command", "args", "env"]),
            definition["type"] == nil || definition["type"] as? String == "stdio",
            let command = definition["command"] as? String,
            let arguments = (definition["args"] ?? [String]()) as? [String],
            let environment = (definition["env"] ?? [String: String]()) as? [String: String]
        else { throw ClaudeMCPConfigurationFailure.unsupportedDefinition }
        return AgentMCPDefinition(command: command, arguments: arguments, environment: environment)
    }

    func shadowingScopes(
        named name: String, workingDirectoryURL: URL
    ) throws -> [ClaudeMCPConfigurationScope] {
        let configuration = try readDictionary(at: configurationURL)
        let projects = try dictionary(configuration, key: "projects")
        let project = try dictionary(projects, key: workingDirectoryURL.standardizedFileURL.path)
        let localServers = try dictionary(project, key: "mcpServers")
        let projectConfiguration = try readDictionary(
            at: workingDirectoryURL.appendingPathComponent(".mcp.json"))
        let projectServers = try dictionary(projectConfiguration, key: "mcpServers")
        return (localServers[name] == nil ? [] : [.local])
            + (projectServers[name] == nil ? [] : [.project])
    }

    private func readDictionary(at fileURL: URL) throws -> [String: Any] {
        let bytes: Data
        do { bytes = try Data(contentsOf: fileURL) } catch CocoaError.fileReadNoSuchFile {
            return [:]
        }
        guard let configuration = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        else { throw ClaudeMCPConfigurationFailure.malformedConfiguration }
        return configuration
    }

    private func dictionary(_ parent: [String: Any], key: String) throws -> [String: Any] {
        guard let entry = parent[key] else { return [:] }
        guard let dictionary = entry as? [String: Any] else {
            throw ClaudeMCPConfigurationFailure.malformedConfiguration
        }
        return dictionary
    }
}
