import Foundation

public struct ObservationCheckpointStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func checkpoint(forWorkspaceAt workspaceURL: URL) throws -> UInt64? {
        storedCheckpoints()[workspaceKey(for: workspaceURL)]
    }

    public func recordCheckpoint(_ checkpoint: UInt64, forWorkspaceAt workspaceURL: URL) throws {
        var checkpoints = storedCheckpoints()
        checkpoints[workspaceKey(for: workspaceURL)] = checkpoint

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(checkpoints).write(to: fileURL, options: .atomic)
    }

    private func storedCheckpoints() -> [String: UInt64] {
        guard let contents = try? Data(contentsOf: fileURL),
            let checkpoints = try? JSONDecoder().decode([String: UInt64].self, from: contents)
        else {
            return [:]
        }

        return checkpoints
    }

    private func workspaceKey(for workspaceURL: URL) -> String {
        workspaceURL.resolvingSymlinksInPath().path()
    }
}
