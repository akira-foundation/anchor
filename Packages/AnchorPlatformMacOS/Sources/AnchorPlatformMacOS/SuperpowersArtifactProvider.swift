import AnchorDomain
import AnchorProvider
import Foundation

public struct SuperpowersArtifactProvider: ArtifactDiscovering {
    private let workspaceURL: URL

    public init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
    }

    public func discoverArtifacts(
        forProject projectID: ProjectID
    ) async throws -> [DiscoveredArtifact] {
        SuperpowersArtifactLocation.allCases.flatMap { location in
            discoverArtifacts(in: location, forProject: projectID)
        }
    }

    private func discoverArtifacts(
        in location: SuperpowersArtifactLocation,
        forProject projectID: ProjectID
    ) -> [DiscoveredArtifact] {
        for pathOnDisk in location.pathsOnDisk {
            let discovered = discoverArtifacts(
                under: pathOnDisk, canonicalPath: location.canonicalPath, forProject: projectID
            )
            guard discovered.isEmpty else { return discovered }
        }

        return []
    }

    private func discoverArtifacts(
        under pathOnDisk: String,
        canonicalPath: String,
        forProject projectID: ProjectID
    ) -> [DiscoveredArtifact] {
        let directoryURL = workspaceURL.appending(path: pathOnDisk)
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directoryURL, includingPropertiesForKeys: nil
            )
        else {
            return []
        }

        return contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { fileURL in
                discoveredArtifact(at: fileURL, canonicalPath: canonicalPath, forProject: projectID)
            }
    }

    private func discoveredArtifact(
        at fileURL: URL,
        canonicalPath: String,
        forProject projectID: ProjectID
    ) -> DiscoveredArtifact? {
        guard let content = try? Data(contentsOf: fileURL) else { return nil }

        let name = "\(canonicalPath)/\(fileURL.lastPathComponent)"
        let artifact = Artifact(
            id: ArtifactID.derived(projectID: projectID, provider: .superpowers, name: name),
            projectID: projectID,
            provider: .superpowers,
            name: name
        )
        guard let artifact else { return nil }

        return DiscoveredArtifact(artifact: artifact, contentHash: ContentHash.digest(of: content))
    }
}
