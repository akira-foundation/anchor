import AnchorDomain
import Foundation
import Testing

@testable import AnchorProvider

@Suite("Provider contracts")
struct ProviderContractTests {
    private let projectID = ProjectID()

    @Test("a provider that only reads is not obliged to materialize")
    func aProviderThatOnlyReadsIsNotObligedToMaterialize() async throws {
        let sessionProvider = ReadOnlySessionProvider(projectID: projectID)

        let discovered = try await sessionProvider.discoverArtifacts(forProject: projectID)
        let entries = try await sessionProvider.classifyKnowledgeEntries(
            in: try #require(discovered.first), content: Data("conversation".utf8)
        )

        #expect(discovered.count == 1)
        #expect(entries.first?.kind == .summary)
    }

    @Test("two providers agree on the digest of identical content")
    func twoProvidersAgreeOnTheDigestOfIdenticalContent() async throws {
        let content = Data("skills/commit-guard/SKILL.md".utf8)
        let claudeSide = ReadOnlySessionProvider(projectID: projectID, content: content)
        let superpowersSide = MaterializingSkillProvider(projectID: projectID, content: content)

        let fromClaude = try await claudeSide.discoverArtifacts(forProject: projectID)
        let fromSuperpowers = try await superpowersSide.discoverArtifacts(forProject: projectID)

        #expect(fromClaude.first?.contentHash == fromSuperpowers.first?.contentHash)
    }

    @Test("discovering unchanged content twice yields the same digest")
    func discoveringUnchangedContentTwiceYieldsTheSameDigest() async throws {
        let provider = MaterializingSkillProvider(projectID: projectID)

        let first = try await provider.discoverArtifacts(forProject: projectID)
        let second = try await provider.discoverArtifacts(forProject: projectID)

        #expect(first.first?.contentHash == second.first?.contentHash)
    }

    @Test("materializing to two destinations does not change the artifact identity")
    func materializingToTwoDestinationsDoesNotChangeTheArtifactIdentity() async throws {
        let provider = MaterializingSkillProvider(projectID: projectID)
        let discovered = try #require(
            try await provider.discoverArtifacts(forProject: projectID).first)
        let content = Data("skill body".utf8)

        try await provider.materializeArtifact(
            discovered.artifact, content: content,
            atDestination: URL(filePath: "/Users/kid/.claude")
        )
        try await provider.materializeArtifact(
            discovered.artifact, content: content, atDestination: URL(filePath: "/Users/kid/.codex")
        )

        let written = await provider.materializations
        #expect(written.count == 2)
        #expect(Set(written.map(\.artifactID)).count == 1)
        #expect(Set(written.map(\.destinationURL)).count == 2)
    }

    @Test("an artifact naming a provider the domain does not know is rejected")
    func anArtifactNamingAProviderTheDomainDoesNotKnowIsRejected() {
        let encoded = Data(
            """
            {"id":"\(ArtifactID().rawValue)","projectID":"\(projectID.rawValue)",\
            "provider":"cursor","name":"session"}
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Artifact.self, from: encoded)
        }
    }
}

private struct ReadOnlySessionProvider: ArtifactDiscovering, ArtifactClassifying {
    let projectID: ProjectID
    var content = Data("conversation".utf8)

    func discoverArtifacts(forProject projectID: ProjectID) async throws -> [DiscoveredArtifact] {
        guard
            let artifact = Artifact(
                id: ArtifactID(), projectID: projectID, provider: .claude, name: "session"
            )
        else {
            return []
        }

        return [
            DiscoveredArtifact(artifact: artifact, contentHash: ContentHash.digest(of: content))
        ]
    }

    func classifyKnowledgeEntries(
        in discoveredArtifact: DiscoveredArtifact,
        content: Data
    ) async throws -> [KnowledgeEntry] {
        [
            KnowledgeEntry(
                id: KnowledgeEntryID(),
                projectID: discoveredArtifact.artifact.projectID,
                kind: .summary,
                summaryText: "one summary per discovered artifact",
                source: .artifact(discoveredArtifact.artifact.id),
                createdAt: Date(timeIntervalSince1970: 0)
            )
        ]
    }
}

private actor MaterializingSkillProvider: ArtifactDiscovering, ArtifactMaterializing {
    struct Materialization: Sendable, Hashable {
        let artifactID: ArtifactID
        let destinationURL: URL
    }

    private let projectID: ProjectID
    private let content: Data
    private let artifactID = ArtifactID()
    private(set) var materializations: [Materialization] = []

    init(projectID: ProjectID, content: Data = Data("skills/commit-guard/SKILL.md".utf8)) {
        self.projectID = projectID
        self.content = content
    }

    func discoverArtifacts(forProject projectID: ProjectID) async throws -> [DiscoveredArtifact] {
        guard
            let artifact = Artifact(
                id: artifactID, projectID: projectID, provider: .superpowers, name: "commit-guard"
            )
        else {
            return []
        }

        return [
            DiscoveredArtifact(artifact: artifact, contentHash: ContentHash.digest(of: content))
        ]
    }

    func materializeArtifact(
        _ artifact: Artifact,
        content: Data,
        atDestination destinationURL: URL
    ) async throws {
        materializations.append(
            Materialization(artifactID: artifact.id, destinationURL: destinationURL)
        )
    }
}
