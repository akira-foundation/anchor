import AnchorDomain
import Foundation

public struct ClaudeSessionArtifacts: Sendable {
    public static let canonicalPrefix = "sessions/claude"

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
            .compactMap { transcript in
                guard let artifact = artifact(for: transcript, forProject: projectID),
                    let content = Self.encode(transcript)
                else { return nil }

                return (artifact, content)
            }
    }

    public static func artifactName(forSession sessionID: SessionID) -> String {
        "\(canonicalPrefix)/\(sessionID.rawValue).json"
    }

    private func transcripts(
        forProject projectID: ProjectID, inWorkspaceAt workspaceURL: URL
    ) -> [ClaudeTranscript] {
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

    private func artifact(
        for transcript: ClaudeTranscript, forProject projectID: ProjectID
    ) -> Artifact? {
        let name = Self.artifactName(forSession: transcript.session.id)

        return Artifact(
            id: ArtifactID.derived(projectID: projectID, provider: .claude, name: name),
            projectID: projectID,
            provider: .claude,
            name: name,
            retention: .latestRevisionOnly
        )
    }

    private static func encode(_ transcript: ClaudeTranscript) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try? encoder.encode(
            ClaudeSessionDocument(
                session: transcript.session,
                messages: transcript.messages.sorted {
                    ($0.timestamp, $0.id.rawValue) < ($1.timestamp, $1.id.rawValue)
                }
            )
        )
    }
}

struct ClaudeSessionDocument: Codable, Sendable {
    let session: AgentSession
    let messages: [ConversationMessage]
}
