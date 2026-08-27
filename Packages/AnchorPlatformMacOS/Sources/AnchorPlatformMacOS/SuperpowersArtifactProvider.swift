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

    func readContent(of artifact: Artifact) -> Data? {
        guard
            let location = SuperpowersArtifactLocation.location(
                forCanonicalPath: artifact.name.split(separator: "/").dropLast().joined(
                    separator: "/")
            )
        else {
            return nil
        }

        let fileName = String(artifact.name.split(separator: "/").last ?? "")
        for pathOnDisk in location.pathsOnDisk {
            let fileURL = workspaceURL.appending(path: pathOnDisk).appending(path: fileName)
            if let content = try? Data(contentsOf: fileURL) { return content }
        }

        return nil
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

        let artifact = Artifact(
            id: ArtifactID(),
            projectID: projectID,
            provider: .superpowers,
            name: "\(canonicalPath)/\(fileURL.lastPathComponent)"
        )
        guard let artifact else { return nil }

        return DiscoveredArtifact(artifact: artifact, contentHash: ContentHash.digest(of: content))
    }
}
