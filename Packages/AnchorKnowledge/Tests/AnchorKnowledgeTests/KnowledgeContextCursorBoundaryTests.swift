import AnchorApplication
import AnchorDomain
import AnchorFoundation
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorKnowledge

@Suite("Knowledge context cursor boundaries")
struct KnowledgeContextCursorBoundaryTests {
    private let projectID = ProjectID.derived(fromSeed: "cursor-project")
    private let workspaceURL = URL(fileURLWithPath: "/tmp/knowledge-cursor-workspace")
    private let generation = ContextReadGeneration(identifier: UUID())

    @Test("cursor binds workspace generation project and both filters")
    func rejectsChangedBindings() async throws {
        let (store, cursor) = try await makeKnowledgeCursor(kind: nil, origin: nil)
        let binding = ContextCursorBinding(workspaceURL: workspaceURL, generation: generation)
        let changedWorkspace = ContextCursorBinding(
            workspaceURL: URL(fileURLWithPath: "/tmp/knowledge-cursor-workspace-sibling"),
            generation: generation)
        let changedGeneration = ContextCursorBinding(
            workspaceURL: workspaceURL,
            generation: ContextReadGeneration(identifier: UUID()))

        for (candidateProject, candidateKind, candidateOrigin, candidateBinding) in [
            (projectID, nil, nil, changedWorkspace),
            (projectID, nil, nil, changedGeneration),
            (ProjectID.derived(fromSeed: "different-project"), nil, nil, binding),
            (projectID, KnowledgeEntryKind.decision, nil, binding),
            (projectID, nil, KnowledgeEntryOrigin.marked, binding),
        ] {
            await #expect(throws: ContextCursorFailure.invalid) {
                try await store.listCurrentKnowledge(
                    forProject: candidateProject, kind: candidateKind,
                    origin: candidateOrigin, page: page(cursor: cursor),
                    binding: candidateBinding)
            }
        }
    }

    @Test("cursor also rejects removal of bound filters")
    func rejectsRemovedFilters() async throws {
        let (store, kindCursor) = try await makeKnowledgeCursor(kind: .decision, origin: nil)
        let (_, originCursor) = try await makeKnowledgeCursor(kind: nil, origin: .marked)
        let binding = ContextCursorBinding(workspaceURL: workspaceURL, generation: generation)

        await #expect(throws: ContextCursorFailure.invalid) {
            try await store.listCurrentKnowledge(
                forProject: projectID, kind: nil, origin: nil,
                page: page(cursor: kindCursor), binding: binding)
        }
        await #expect(throws: ContextCursorFailure.invalid) {
            try await store.listCurrentKnowledge(
                forProject: projectID, kind: nil, origin: nil,
                page: page(cursor: originCursor), binding: binding)
        }
    }

    @Test("artifact cursor cannot page knowledge")
    func rejectsOtherOperationCursor() async throws {
        let (knowledgeStore, _) = try await makeKnowledgeCursor(kind: nil, origin: nil)
        let artifactStore = try await SQLiteArtifactContextStore(
            database: try SQLiteDatabase(fileURL: nil))
        let firstArtifact = try #require(
            Artifact(
                id: ArtifactID(), projectID: projectID, provider: .codex, name: "first.md"))
        let secondArtifact = try #require(
            Artifact(
                id: ArtifactID(), projectID: projectID, provider: .codex, name: "second.md"))
        let firstRevision = try revision(for: firstArtifact, timestamp: 200)
        let secondRevision = try revision(for: secondArtifact, timestamp: 100)
        try await artifactStore.indexArtifactRevisions([
            RecordedArtifactRevision(artifact: firstArtifact, revision: firstRevision),
            RecordedArtifactRevision(artifact: secondArtifact, revision: secondRevision),
        ])
        let binding = ContextCursorBinding(workspaceURL: workspaceURL, generation: generation)
        let artifactPage = try await artifactStore.listArtifacts(
            forProject: projectID, provider: nil, page: page(), binding: binding)
        let artifactCursor = try #require(artifactPage.nextCursor)

        await #expect(throws: ContextCursorFailure.invalid) {
            try await knowledgeStore.listCurrentKnowledge(
                forProject: projectID, kind: nil, origin: nil,
                page: page(cursor: artifactCursor), binding: binding)
        }
    }

    @Test("malformed encoding and payload fields are invalid")
    func rejectsMalformedTokens() async throws {
        let (store, cursor) = try await makeKnowledgeCursor(kind: nil, origin: nil)
        let binding = ContextCursorBinding(workspaceURL: workspaceURL, generation: generation)
        let malformed = [
            ContextPageCursor(rawValue: "%%%")!,
            ContextPageCursor(rawValue: "YWJj+")!,
            ContextPageCursor(rawValue: "YWJj/")!,
            try tampered(cursor, field: "version", replacement: 99),
            try tampered(cursor, field: "operation", replacement: "list-artifacts"),
            try tampered(cursor, field: "knowledgeEntryID", replacement: ""),
        ]
        for token in malformed {
            await #expect(throws: ContextCursorFailure.invalid) {
                try await store.listCurrentKnowledge(
                    forProject: projectID, kind: nil, origin: nil,
                    page: page(cursor: token), binding: binding)
            }
        }
    }

    private func makeKnowledgeCursor(
        kind: KnowledgeEntryKind?, origin: KnowledgeEntryOrigin?
    ) async throws -> (SQLiteKnowledgeStore, ContextPageCursor) {
        let store = try await SQLiteKnowledgeStore(database: try SQLiteDatabase(fileURL: nil))
        let entries = ["first", "second"].enumerated().map { index, seed in
            KnowledgeEntry(
                id: .derived(fromSeed: seed), projectID: projectID,
                kind: .decision, summaryText: seed,
                source: .artifact(.derived(fromSeed: seed)),
                sourceContentHash: .digest(of: Data(seed.utf8)), origin: .marked,
                createdAt: Date(timeIntervalSince1970: TimeInterval(200 - index * 100)))
        }
        try await store.recordEntries(
            entries,
            supersedingEntriesFrom: .artifact(
                ArtifactID.derived(fromSeed: "unused")))
        let firstPage = try await store.listCurrentKnowledge(
            forProject: projectID, kind: kind, origin: origin, page: page(),
            binding: ContextCursorBinding(workspaceURL: workspaceURL, generation: generation))
        return (store, try #require(firstPage.nextCursor))
    }

    private func revision(
        for artifact: Artifact, timestamp: TimeInterval
    ) throws -> ArtifactRevision {
        try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: artifact.id, parentRevisionID: nil,
                contentHash: .digest(of: Data(artifact.name.utf8)), deviceID: DeviceID(),
                createdAt: Date(timeIntervalSince1970: timestamp), retention: artifact.retention))
    }

    private func tampered(
        _ cursor: ContextPageCursor, field: String, replacement: Any
    ) throws -> ContextPageCursor {
        var encoded = cursor.rawValue.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded.append(String(repeating: "=", count: (4 - encoded.count % 4) % 4))
        let bytes = try #require(Data(base64Encoded: encoded))
        var cursorFields = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        cursorFields[field] = replacement
        let changedBytes = try JSONSerialization.data(withJSONObject: cursorFields)
        let token = changedBytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return try #require(ContextPageCursor(rawValue: token))
    }

    private func page(cursor: ContextPageCursor? = nil) -> ContextPageRequest {
        ContextPageRequest(limit: 1, cursor: cursor, maximumLimit: 100)!
    }
}
