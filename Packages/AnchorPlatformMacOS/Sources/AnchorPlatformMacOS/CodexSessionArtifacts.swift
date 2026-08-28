import AnchorDomain
import Foundation

public struct CodexSessionArtifacts: Sendable {
    private static let originProbeByteCount = 65_536

    private let root: URL
    private let reader: CodexTranscriptReader

    public init(
        root: URL = CodexSessionArtifacts.defaultRoot,
        reader: CodexTranscriptReader = CodexTranscriptReader()
    ) {
        self.root = root
        self.reader = reader
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions")
    }

    public func sessionArtifacts(
        forProject projectID: ProjectID, inWorkspaceAt workspaceURL: URL
    ) -> [(artifact: Artifact, content: Data)] {
        rolloutsBelongingToWorkspace(at: workspaceURL)
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .compactMap { reader.transcript(inLineDelimitedJSON: $0, forProject: projectID) }
            .compactMap { SessionArtifact.make(from: $0, forProject: projectID) }
    }

    private func rolloutsBelongingToWorkspace(at workspaceURL: URL) -> [URL] {
        let wanted = Self.comparablePath(of: workspaceURL)

        return rolloutFiles().filter { fileURL in
            guard let origin = reader.origin(inLineDelimitedJSON: openingLines(of: fileURL)) else {
                return false
            }

            return origin.startedByAPerson
                && Self.comparablePath(of: URL(filePath: origin.workingDirectory)) == wanted
        }
    }

    private static func comparablePath(of url: URL) -> String {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            .path(percentEncoded: false)

        return resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
    }

    private func rolloutFiles() -> [URL] {
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return [] }

        return walker.allObjects
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.path() < $1.path() }
    }

    private func openingLines(of fileURL: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return "" }

        defer { try? handle.close() }

        let opening = (try? handle.read(upToCount: Self.originProbeByteCount)) ?? Data()

        return String(decoding: opening, as: UTF8.self)
    }
}
