import AnchorDomain
import AnchorPersistence
import AnchorProvider
import Foundation

public struct CodexSessionArtifacts: Sendable {
    private static let originProbeByteCount = 65_536

    private let root: URL
    private let reader: CodexTranscriptReader
    private let index: SessionFileIndex?

    public init(
        root: URL = CodexSessionArtifacts.defaultRoot,
        reader: CodexTranscriptReader = CodexTranscriptReader(),
        index: SessionFileIndex? = nil
    ) {
        self.root = root
        self.reader = reader
        self.index = index
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions")
    }

    public func discoveredArtifacts(
        forProject projectID: ProjectID, inWorkspaceAt workspaceURL: URL
    ) async throws -> [DiscoveredArtifact] {
        var discovered: [DiscoveredArtifact] = []

        for fileURL in rolloutFiles() {
            let recalled = try await recalledArtifact(at: fileURL, forProject: projectID)

            guard recalled == nil else {
                discovered += [recalled].compactMap { $0 }
                continue
            }

            discovered += try await readArtifacts(
                at: fileURL, forProject: projectID, inWorkspaceAt: workspaceURL)
        }

        return discovered
    }

    public func sessionArtifacts(
        forProject projectID: ProjectID, inWorkspaceAt workspaceURL: URL
    ) -> [(artifact: Artifact, content: Data)] {
        rolloutFiles()
            .filter { belongsToWorkspace(at: workspaceURL, fileURL: $0) }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .compactMap { reader.transcript(inLineDelimitedJSON: $0, forProject: projectID) }
            .compactMap { SessionArtifact.make(from: $0, forProject: projectID) }
    }

    private func recalledArtifact(
        at fileURL: URL, forProject projectID: ProjectID
    ) async throws -> DiscoveredArtifact? {
        guard let index,
            let stamp = Self.stamp(of: fileURL),
            let recorded = try await index.recordedFile(
                atPath: WorkspacePath.comparable(fileURL)),
            recorded.describesFile(byteSize: stamp.byteSize, modifiedAt: stamp.modifiedAt),
            let contentHash = ContentHash(rawValue: recorded.contentHash),
            let artifact = Artifact(
                id: ArtifactID.derived(
                    projectID: projectID, provider: .codex, name: recorded.artifactName),
                projectID: projectID,
                provider: .codex,
                name: recorded.artifactName,
                retention: .latestRevisionOnly
            )
        else { return nil }

        return DiscoveredArtifact(artifact: artifact, contentHash: contentHash)
    }

    private func readArtifacts(
        at fileURL: URL, forProject projectID: ProjectID, inWorkspaceAt workspaceURL: URL
    ) async throws -> [DiscoveredArtifact] {
        guard belongsToWorkspace(at: workspaceURL, fileURL: fileURL),
            let text = try? String(contentsOf: fileURL, encoding: .utf8),
            let transcript = reader.transcript(inLineDelimitedJSON: text, forProject: projectID),
            let made = SessionArtifact.make(from: transcript, forProject: projectID)
        else { return [] }

        let contentHash = ContentHash.digest(of: made.content)

        if let index, let stamp = Self.stamp(of: fileURL) {
            try await index.record(
                RecordedSessionFile(
                    path: WorkspacePath.comparable(fileURL),
                    byteSize: stamp.byteSize,
                    modifiedAt: stamp.modifiedAt,
                    artifactName: made.artifact.name,
                    contentHash: contentHash.rawValue
                )
            )
        }

        return [DiscoveredArtifact(artifact: made.artifact, contentHash: contentHash)]
    }

    private func belongsToWorkspace(at workspaceURL: URL, fileURL: URL) -> Bool {
        guard let origin = reader.origin(inLineDelimitedJSON: openingLines(of: fileURL)) else {
            return false
        }

        return WorkspacePath.comparable(URL(filePath: origin.workingDirectory))
            == WorkspacePath.comparable(workspaceURL)
    }

    private static func stamp(of fileURL: URL) -> (byteSize: Int64, modifiedAt: Date)? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: WorkspacePath.comparable(fileURL)),
            let byteSize = (attributes[.size] as? NSNumber)?.int64Value,
            let modifiedAt = attributes[.modificationDate] as? Date
        else { return nil }

        return (byteSize, modifiedAt)
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
