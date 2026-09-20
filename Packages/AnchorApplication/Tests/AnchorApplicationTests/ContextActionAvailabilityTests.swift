import Foundation
import Testing

@testable import AnchorApplication

@Suite("Query generation boundaries")
struct ContextActionAvailabilityTests {
    @Test("every query action refuses a generation change", arguments: 0..<8)
    func everyActionRequiresOneGeneration(operation: Int) async throws {
        let fixture = try ContextQueryFixture()
        let availability = ChangingContextAvailability()
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            switch operation {
            case 0:
                _ = try await ResolveCurrentProjectAction(
                    workspace: fixture, availability: availability
                )
                .perform(ProjectContextRequest())
            case 1:
                _ = try await BuildMinimalProjectResumeAction(
                    workspace: fixture, sessions: fixture, availability: availability
                )
                .perform(ProjectContextRequest())
            case 2:
                _ = try await SearchProjectContextAction(
                    workspace: fixture, search: QuerySearchSpy(), availability: availability
                )
                .perform(try #require(SearchProjectContextRequest(text: "needle")))
            case 3:
                _ = try await ListProjectArtifactsAction(
                    workspace: fixture, artifacts: fixture, availability: availability
                )
                .perform(try #require(ListProjectArtifactsRequest()))
            case 4:
                _ = try await ReadProjectArtifactAction(
                    workspace: fixture, artifacts: fixture, content: fixture,
                    availability: availability
                )
                .perform(try #require(ReadProjectArtifactRequest(artifactID: fixture.artifact.id)))
            case 5:
                _ = try await ListProjectSessionsAction(
                    workspace: fixture, sessions: fixture, availability: availability
                )
                .perform(try #require(ListProjectSessionsRequest()))
            case 6:
                _ = try await ReadProjectSessionAction(
                    workspace: fixture, sessions: fixture, availability: availability
                )
                .perform(ReadProjectSessionRequest(sessionID: fixture.session.id))
            default:
                _ = try await ReadSessionMessagesAction(
                    workspace: fixture, entries: fixture, availability: availability
                )
                .perform(try #require(ReadSessionMessagesRequest(sessionID: fixture.session.id)))
            }
        }
    }
}

private actor ChangingContextAvailability: ContextAvailabilityReading {
    func loadAvailableGeneration() async throws -> ContextReadGeneration {
        ContextReadGeneration(identifier: UUID())
    }
}
