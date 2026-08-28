import AnchorApplication
import AnchorDomain
import AnchorProvider
import Foundation

public struct CompositeArtifactDiscoverer: ArtifactDiscovering {
    private let discoverers: [any ArtifactDiscovering]

    public init(_ discoverers: [any ArtifactDiscovering]) {
        self.discoverers = discoverers
    }

    public func discoverArtifacts(
        forProject projectID: ProjectID
    ) async throws -> [DiscoveredArtifact] {
        var discovered: [DiscoveredArtifact] = []

        for discoverer in discoverers {
            discovered += try await discoverer.discoverArtifacts(forProject: projectID)
        }

        return discovered
    }
}

public struct CompositeArtifactContentReader: ArtifactContentReading {
    private let readers: [any ArtifactContentReading]

    public init(_ readers: [any ArtifactContentReading]) {
        self.readers = readers
    }

    public func readContent(
        ofArtifactNamed name: String,
        inWorkspaceAt workspaceURL: URL
    ) async throws -> Data? {
        for reader in readers {
            if let content = try await reader.readContent(
                ofArtifactNamed: name, inWorkspaceAt: workspaceURL)
            {
                return content
            }
        }

        return nil
    }
}
