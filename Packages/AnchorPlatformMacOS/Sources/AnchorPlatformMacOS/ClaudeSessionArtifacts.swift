import AnchorDomain
import Foundation

public struct ClaudeSessionArtifacts: Sendable {
    private let root: URL
    private let reader: ClaudeTranscriptReader

    public init(
        root: URL = ClaudeSessionsLocation.defaultRoot,
        reader: ClaudeTranscriptReader = ClaudeTranscriptReader()
    ) {
        self.root = root
        self.reader = reader
    }

    public func sessionArtifacts(
        forProject projectID: ProjectID, inWorkspaceAt workspaceURL: URL
    ) -> [(artifact: Artifact, content: Data)] {
        transcripts(forProject: projectID, inWorkspaceAt: workspaceURL)
            .compactMap { SessionArtifact.make(from: $0, forProject: projectID) }
    }

    private func transcripts(
        forProject projectID: ProjectID, inWorkspaceAt workspaceURL: URL
    ) -> [AgentTranscript] {
        guard
            let directory = ClaudeSessionsLocation.directoryURL(
                forWorkspaceAt: workspaceURL, under: root),
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return [] }

        return files.filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { reader.transcripts(inLineDelimitedJSON: $0, forProject: projectID) }
    }
}
