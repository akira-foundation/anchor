import Foundation
import Testing

@testable import AnchorDomain

@Suite("Domain model coding")
struct DomainCodableTests {
    private static let digest = String(repeating: "a1b2c3d4", count: 8)
    private static let fixedDate = Date(timeIntervalSince1970: 1_754_611_200)

    private func assertRoundTrip<Model: Codable & Equatable>(_ model: Model) throws {
        let encodedModel = try JSONEncoder().encode(model)
        let decodedModel = try JSONDecoder().decode(Model.self, from: encodedModel)

        #expect(decodedModel == model)
    }

    @Test("a project survives an encode and decode round trip")
    func projectSurvivesAnEncodeAndDecodeRoundTrip() throws {
        try assertRoundTrip(
            Project(
                id: ProjectID(),
                displayName: "Anchor",
                canonicalRepositoryRemote: try #require(
                    CanonicalRepositoryRemote(rawValue: "github.com/akira-foundation/anchor")
                )
            )
        )
    }

    @Test("a device survives an encode and decode round trip")
    func deviceSurvivesAnEncodeAndDecodeRoundTrip() throws {
        try assertRoundTrip(
            Device(id: DeviceID(), displayName: "MacBook Pro", platform: .macOS)
        )
    }

    @Test("a workspace without a local repository survives an encode and decode round trip")
    func workspaceWithoutALocalRepositorySurvivesAnEncodeAndDecodeRoundTrip() throws {
        try assertRoundTrip(
            Workspace(
                id: WorkspaceID(), projectID: ProjectID(), deviceID: DeviceID(),
                localRepositoryURL: nil)
        )
    }

    @Test("an artifact revision survives an encode and decode round trip")
    func artifactRevisionSurvivesAnEncodeAndDecodeRoundTrip() throws {
        let contentHash = try #require(ContentHash(rawValue: Self.digest))
        let revision = try #require(
            ArtifactRevision(
                id: RevisionID(),
                artifactID: ArtifactID(),
                parentRevisionID: RevisionID(),
                contentHash: contentHash,
                deviceID: DeviceID(),
                createdAt: Self.fixedDate
            )
        )

        try assertRoundTrip(revision)
    }

    @Test("an agent session survives an encode and decode round trip")
    func agentSessionSurvivesAnEncodeAndDecodeRoundTrip() throws {
        try assertRoundTrip(
            AgentSession(
                id: SessionID(),
                projectID: ProjectID(),
                provider: .claude,
                startedAt: Self.fixedDate,
                updatedAt: Self.fixedDate
            )
        )
    }

    @Test("a conversation message survives an encode and decode round trip")
    func conversationMessageSurvivesAnEncodeAndDecodeRoundTrip() throws {
        try assertRoundTrip(
            ConversationMessage(
                id: MessageID(),
                sessionID: SessionID(),
                role: .assistant,
                content: "Phase 02 implements the shared domain.",
                timestamp: Self.fixedDate
            )
        )
    }

    @Test("a knowledge entry survives an encode and decode round trip")
    func knowledgeEntrySurvivesAnEncodeAndDecodeRoundTrip() throws {
        try assertRoundTrip(
            KnowledgeEntry(
                id: KnowledgeEntryID(),
                projectID: ProjectID(),
                kind: .architecture,
                summaryText: "AnchorDomain depends only on AnchorFoundation",
                source: .session(SessionID()),
                sourceContentHash: ContentHash.digest(of: Data("source".utf8)),
                createdAt: Self.fixedDate
            )
        )
    }

    @Test("a sync operation survives an encode and decode round trip")
    func syncOperationSurvivesAnEncodeAndDecodeRoundTrip() throws {
        let contentHash = try #require(ContentHash(rawValue: Self.digest))
        let storageKey = try #require(StorageKey(rawValue: "projects/anchor/artifacts/index"))

        try assertRoundTrip(
            SyncOperation(
                id: SyncOperationID(),
                artifactID: ArtifactID(),
                revisionID: RevisionID(),
                storageKey: storageKey,
                contentHash: contentHash,
                state: .pending,
                queuedAt: Self.fixedDate
            )
        )
    }

    @Test("a device presence survives an encode and decode round trip")
    func devicePresenceSurvivesAnEncodeAndDecodeRoundTrip() throws {
        try assertRoundTrip(
            DevicePresence(
                projectID: ProjectID(), deviceID: DeviceID(), lastSeenAt: Self.fixedDate)
        )
    }
}

@Suite("Domain optional field coding")
struct DomainOptionalFieldCodableTests {
    private static let digest = String(repeating: "a1b2c3d4", count: 8)
    private static let fixedDate = Date(timeIntervalSince1970: 1_754_611_200)

    private func assertRoundTrip<Model: Codable & Equatable>(_ model: Model) throws {
        let encodedModel = try JSONEncoder().encode(model)
        let decodedModel = try JSONDecoder().decode(Model.self, from: encodedModel)

        #expect(decodedModel == model)
    }

    @Test("a workspace with a local repository survives an encode and decode round trip")
    func workspaceWithALocalRepositorySurvivesAnEncodeAndDecodeRoundTrip() throws {
        try assertRoundTrip(
            Workspace(
                id: WorkspaceID(),
                projectID: ProjectID(),
                deviceID: DeviceID(),
                localRepositoryURL: URL(filePath: "/Users/kid/Developer/anchor")
            )
        )
    }

    @Test("an ancestry root revision survives an encode and decode round trip")
    func ancestryRootRevisionSurvivesAnEncodeAndDecodeRoundTrip() throws {
        let contentHash = try #require(ContentHash(rawValue: Self.digest))
        let rootRevision = try #require(
            ArtifactRevision(
                id: RevisionID(),
                artifactID: ArtifactID(),
                parentRevisionID: nil,
                contentHash: contentHash,
                deviceID: DeviceID(),
                createdAt: Self.fixedDate
            )
        )

        try assertRoundTrip(rootRevision)
    }

    @Test("a knowledge entry sourced from an artifact survives an encode and decode round trip")
    func knowledgeEntrySourcedFromAnArtifactSurvivesAnEncodeAndDecodeRoundTrip() throws {
        try assertRoundTrip(
            KnowledgeEntry(
                id: KnowledgeEntryID(),
                projectID: ProjectID(),
                kind: .decision,
                summaryText: "SQLite backs the local index",
                source: .artifact(ArtifactID()),
                sourceContentHash: ContentHash.digest(of: Data("source".utf8)),
                createdAt: Self.fixedDate
            )
        )
    }

}
