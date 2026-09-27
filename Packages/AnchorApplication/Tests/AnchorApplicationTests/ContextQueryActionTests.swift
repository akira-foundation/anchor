import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

@Suite("Context query actions")
struct ContextQueryActionTests {
    @Test("search rejects blank text and limits above one hundred")
    func searchRejectsInvalidArguments() async throws {
        #expect(SearchProjectContextRequest(text: " \n") == nil)
        #expect(SearchProjectContextRequest(text: "plan", limit: 0) == nil)
        #expect(SearchProjectContextRequest(text: "plan", limit: 101) == nil)
        let fixture = try ContextQueryFixture()
        let search = QuerySearchSpy()
        let action = SearchProjectContextAction(
            workspace: fixture, search: search, availability: fixture)
        _ = try await action.perform(try #require(SearchProjectContextRequest(text: "plan")))
        #expect(await search.requestedLimit == 20)
        #expect(await search.requestedProject == fixture.project.projectID)
    }

    @Test("artifact reading defaults to current revision")
    func artifactReadingUsesCurrentRevisionWhenRevisionIsAbsent() async throws {
        let fixture = try ContextQueryFixture()
        let action = fixture.artifactAction
        let chunk = try await action.perform(
            try #require(ReadProjectArtifactRequest(artifactID: fixture.artifact.id)))
        #expect(chunk.revision.id == fixture.revision.id)
        #expect(chunk.text == "ab😀cd")
        #expect(chunk.nextCursor == nil)
        #expect(!chunk.isTruncated)
    }

    @Test("artifact chunks never split a UTF8 scalar")
    func artifactChunkEndsOnAUTF8Boundary() async throws {
        let fixture = try ContextQueryFixture()
        let first = try await fixture.artifactAction.perform(
            try #require(ReadProjectArtifactRequest(artifactID: fixture.artifact.id, byteLimit: 4)))
        #expect(first.text == "ab")
        #expect(first.isTruncated)
        let second = try await fixture.artifactAction.perform(
            try #require(
                ReadProjectArtifactRequest(
                    artifactID: fixture.artifact.id, cursor: first.nextCursor, byteLimit: 4)))
        #expect(second.text == "😀")
        let third = try await fixture.artifactAction.perform(
            try #require(
                ReadProjectArtifactRequest(
                    artifactID: fixture.artifact.id, cursor: second.nextCursor, byteLimit: 4)))
        #expect(third.text == "cd")
        #expect(third.nextCursor == nil)
    }

    @Test("message listing rejects limits above two hundred")
    func messageListingRejectsOversizedPage() async throws {
        let fixture = try ContextQueryFixture()
        #expect(ReadSessionMessagesRequest(sessionID: fixture.session.id, limit: 201) == nil)
        #expect(ReadSessionMessagesRequest(sessionID: fixture.session.id, limit: 0) == nil)
        let messages = try await ReadSessionMessagesAction(
            workspace: fixture, entries: fixture, availability: fixture
        )
        .perform(try #require(ReadSessionMessagesRequest(sessionID: fixture.session.id)))
        #expect(messages.records.count == 50)
    }

    @Test("list requests enforce defaults and maxima")
    func listsValidateBounds() async throws {
        let fixture = try ContextQueryFixture()
        #expect(ListProjectArtifactsRequest(limit: 101) == nil)
        #expect(ListProjectSessionsRequest(limit: 101) == nil)
        #expect(ListProjectArtifactsRequest(limit: 0) == nil)
        #expect(ListProjectSessionsRequest(limit: 0) == nil)
        #expect(
            ReadProjectArtifactRequest(artifactID: fixture.artifact.id, byteLimit: 65_537) == nil)
        #expect(ReadProjectArtifactRequest(artifactID: fixture.artifact.id, byteLimit: 3) == nil)
        #expect(ReadProjectArtifactRequest(artifactID: fixture.artifact.id, byteLimit: 4) != nil)
        #expect(ReadProjectArtifactRequest(artifactID: fixture.artifact.id)?.byteLimit == 16_384)
        let artifacts = try await ListProjectArtifactsAction(
            workspace: fixture, artifacts: fixture, availability: fixture
        )
        .perform(try #require(ListProjectArtifactsRequest()))
        let sessions = try await ListProjectSessionsAction(
            workspace: fixture, sessions: fixture, availability: fixture
        )
        .perform(try #require(ListProjectSessionsRequest()))
        #expect(artifacts.records.count == 20)
        #expect(sessions.records.count == 20)
        #expect(
            try await ResolveCurrentProjectAction(workspace: fixture, availability: fixture)
                .perform(ProjectContextRequest()) == fixture.project)
    }

    @Test("artifact metadata and revision ownership precede content reads")
    func artifactOwnershipPrecedesContent() async throws {
        let fixture = try ContextQueryFixture()
        let content = QueryContentSpy(revision: fixture.unrelatedRevision)
        let action = ReadProjectArtifactAction(
            workspace: fixture, artifacts: fixture, content: content, availability: fixture)
        await #expect(throws: ContextQueryFailure.entityNotFound) {
            try await action.perform(
                try #require(ReadProjectArtifactRequest(artifactID: ArtifactID())))
        }
        await #expect(throws: ContextQueryFailure.entityNotFound) {
            try await action.perform(
                try #require(
                    ReadProjectArtifactRequest(
                        artifactID: fixture.artifact.id, revisionID: fixture.unrelatedRevision.id)))
        }
        #expect(await content.contentReads == 0)
        #expect(await content.revisionReads == 1)
    }

    @Test("artifact content rejects binary bytes and malformed or cross-artifact cursors")
    func artifactContentRejectsInvalidContentAndCursors() async throws {
        let fixture = try ContextQueryFixture()
        let content = QueryContentSpy(revision: fixture.revision, bytes: Data([0xff]))
        await #expect(throws: ContextQueryFailure.contentIsNotText) {
            try await ReadProjectArtifactAction(
                workspace: fixture, artifacts: fixture, content: content, availability: fixture
            )
            .perform(try #require(ReadProjectArtifactRequest(artifactID: fixture.artifact.id)))
        }
        await #expect(throws: ContextQueryFailure.invalidCursor) {
            try await fixture.artifactAction.perform(
                try #require(
                    ReadProjectArtifactRequest(
                        artifactID: fixture.artifact.id,
                        cursor: ContextPageCursor(rawValue: "invalid"))))
        }
    }

    @Test("legacy artifact cursors expire instead of resuming a new read model")
    func legacyArtifactCursorIsInvalid() async throws {
        let fixture = try ContextQueryFixture()
        let legacyPayload = """
            {"version":1,"operation":"read-artifact","project":"\(fixture.project.projectID.rawValue)","artifact":"\(fixture.artifact.id.rawValue)","revision":"\(fixture.revision.id.rawValue)","offset":2}
            """
        let token = Data(legacyPayload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        await #expect(throws: ContextQueryFailure.invalidCursor) {
            try await fixture.artifactAction.perform(
                try #require(
                    ReadProjectArtifactRequest(
                        artifactID: fixture.artifact.id,
                        cursor: ContextPageCursor(rawValue: token))))
        }
    }

    @Test("artifact chunks reject sibling workspaces and expired generations")
    func artifactCursorScopeMustMatch() async throws {
        let fixture = try ContextQueryFixture()
        let firstChunk = try await fixture.artifactAction.perform(
            try #require(
                ReadProjectArtifactRequest(
                    artifactID: fixture.artifact.id, byteLimit: 4)))
        let cursor = try #require(firstChunk.nextCursor)
        let siblingProject = ProjectContext(
            projectID: fixture.project.projectID,
            displayName: fixture.project.displayName,
            canonicalRepositoryRemote: nil,
            workspaceURL: URL(filePath: "/sibling/query"))
        let siblingScope = CursorScope(project: siblingProject, generation: fixture.generation)
        let expiredScope = CursorScope(
            project: fixture.project,
            generation: ContextReadGeneration(identifier: UUID()))
        for scope in [siblingScope, expiredScope] {
            let action = ReadProjectArtifactAction(
                workspace: scope, artifacts: fixture, content: fixture,
                availability: scope)
            await #expect(throws: ContextQueryFailure.invalidCursor) {
                try await action.perform(
                    try #require(
                        ReadProjectArtifactRequest(
                            artifactID: fixture.artifact.id, cursor: cursor, byteLimit: 4)))
            }
        }
    }

    @Test("session queries refuse entities outside the authorized project")
    func sessionOwnershipIsRequired() async throws {
        let fixture = try ContextQueryFixture()
        await #expect(throws: ContextQueryFailure.entityNotFound) {
            try await ReadProjectSessionAction(
                workspace: fixture, sessions: fixture, availability: fixture
            )
            .perform(ReadProjectSessionRequest(sessionID: SessionID()))
        }
        await #expect(throws: ContextQueryFailure.entityNotFound) {
            try await ReadSessionMessagesAction(
                workspace: fixture, entries: fixture, availability: fixture
            )
            .perform(try #require(ReadSessionMessagesRequest(sessionID: SessionID())))
        }
    }

    @Test("session details preserve canonical message and tool counts")
    func sessionDetailsPreserveCounts() async throws {
        let fixture = try ContextQueryFixture()
        let record = try await ReadProjectSessionAction(
            workspace: fixture, sessions: fixture, availability: fixture
        )
        .perform(ReadProjectSessionRequest(sessionID: fixture.session.id))
        #expect(record.messageCount == 7)
        #expect(record.toolActivityCount == 3)
    }

    @Test("query failures preserve cursor and availability errors and hide driver errors")
    func mapsQueryFailures() async throws {
        let fixture = try ContextQueryFixture()
        for (failure, expected) in [
            (QuerySearchSpy.Failure.cursor, ContextQueryFailure.invalidCursor),
            (.storage, .readFailed), (.unavailable, .contextUnavailable),
        ] {
            let action = SearchProjectContextAction(
                workspace: fixture, search: QuerySearchSpy(failure: failure), availability: fixture)
            await #expect(throws: expected) {
                try await action.perform(try #require(SearchProjectContextRequest(text: "plan")))
            }
        }
    }
}

private struct CursorScope: AuthorizedProjectContextReading, ContextAvailabilityReading {
    let project: ProjectContext
    let generation: ContextReadGeneration

    func loadAuthorizedProjectContext() async throws -> ProjectContext { project }
    func loadAvailableGeneration() async throws -> ContextReadGeneration { generation }
}
