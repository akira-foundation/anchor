import AnchorMCPServerCore
import AnchorPlatformMacOS
import Darwin
import Foundation

@main
enum AnchorMCPServerMain {
    private enum StartupFailure: Error {
        case supportDirectoryUnavailable
    }

    static func main() async {
        do {
            let arguments = try AnchorMCPArguments(CommandLine.arguments)
            let supportDirectoryURL = try supportDirectoryURL()
            let encryptionKeys = SynchronizedEncryptionKeyStore()
            let reader = try await ContextReadModelAssembly.openReader(
                requestedWorkspacePath: arguments.workspacePath,
                supportDirectoryURL: supportDirectoryURL,
                configurationURL: ObservedWorkspaceConfiguration.defaultFileURL(
                    inSupportDirectoryAt: supportDirectoryURL),
                keyLoader: {
                    #if DEBUG
                        if ProcessInfo.processInfo.environment[
                            "ANCHOR_MCP_TEST_SUPPORT_DIRECTORY"] != nil
                        {
                            return nil
                        }
                    #endif
                    return try encryptionKeys.existingKey()
                })
            let server = AnchorMCPServer(
                actions: ContextQueryActions(
                    currentProject: reader.currentProject, resume: reader.resume,
                    search: reader.search, listArtifacts: reader.listArtifacts,
                    readArtifact: reader.readArtifact, listSessions: reader.listSessions,
                    readSession: reader.readSession, readMessages: reader.readMessages,
                    listKnowledge: reader.listKnowledge, readKnowledge: reader.readKnowledge))
            try await server.runStandardInputOutput()
        } catch {
            FileHandle.standardError.write(Data("Anchor MCP server could not start.\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func supportDirectoryURL() throws -> URL {
        #if DEBUG
            if let testSupportPath = ProcessInfo.processInfo.environment[
                "ANCHOR_MCP_TEST_SUPPORT_DIRECTORY"]
            {
                return URL(filePath: testSupportPath)
            }
        #endif
        guard
            let applicationSupportURL = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else { throw StartupFailure.supportDirectoryUnavailable }
        return applicationSupportURL.appending(path: "Anchor")
    }
}
