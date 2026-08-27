import AnchorApplication
import Foundation

public struct WorkspaceFileContentReader: ArtifactContentReading {
    public init() {}

    public func readContent(
        ofArtifactNamed name: String,
        inWorkspaceAt workspaceURL: URL
    ) async throws -> Data? {
        for candidate in WorkspacePathSpelling.spellingsOnDisk(of: name) {
            if let contents = try? Data(contentsOf: workspaceURL.appending(path: candidate)) {
                return contents
            }
        }

        return nil
    }
}
