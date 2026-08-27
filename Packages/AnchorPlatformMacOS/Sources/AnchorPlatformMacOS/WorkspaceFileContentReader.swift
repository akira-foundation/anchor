import AnchorApplication
import Foundation

public struct WorkspaceFileContentReader: ArtifactContentReading {
    public init() {}

    public func readContent(
        ofArtifactNamed name: String,
        inWorkspaceAt workspaceURL: URL
    ) async throws -> Data? {
        for candidate in candidatePaths(for: name) {
            if let contents = try? Data(contentsOf: workspaceURL.appending(path: candidate)) {
                return contents
            }
        }

        return nil
    }

    private func candidatePaths(for name: String) -> [String] {
        guard name.hasPrefix("docs/") else { return [name] }

        return [name, "D" + name.dropFirst()]
    }
}
