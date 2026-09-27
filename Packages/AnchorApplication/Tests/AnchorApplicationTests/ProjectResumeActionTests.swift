import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

@Suite("Project resume action")
struct ProjectResumeActionTests {
    @Test("resume authorizes once and applies the compact policy")
    func resumeUsesAuthorizedProjectAndCompactLimits() async throws {
        let fixture = try ContextQueryFixture()
        let expectedResume = ProjectResume(project: fixture.project)
        let reader = ProjectResumeReaderSpy(resume: expectedResume)
        let resume = try await BuildProjectResumeAction(
            workspace: fixture, resumes: reader, availability: fixture
        ).perform(ProjectContextRequest())
        #expect(await reader.requestedProjects == [fixture.project])
        #expect(await reader.requestedLimits == [.compact])
        #expect(resume.project == fixture.project)
    }

    @Test("resume derives activity and agent without inventing missing context")
    func resumeDerivesStableOptionalFields() async throws {
        let fixture = try ContextQueryFixture()
        let presence = DevicePresence(
            projectID: fixture.project.projectID, deviceID: DeviceID(),
            lastSeenAt: Date(timeIntervalSince1970: 30))
        let populated = ProjectResume(
            project: fixture.project,
            recentSession: SessionContextRecord(session: fixture.session),
            lastPresence: presence,
            latestArtifactRevisionAt: Date(timeIntervalSince1970: 40),
            latestKnowledgeEntryAt: Date(timeIntervalSince1970: 35))
        let empty = ProjectResume(project: fixture.project)
        #expect(populated.lastActivityAt == Date(timeIntervalSince1970: 40))
        #expect(populated.lastAgentProvider == .codex)
        #expect(empty.lastActivityAt == nil)
        #expect(empty.lastAgentProvider == nil)
    }

    @Test("resume knowledge summaries stay within the UTF8 byte policy")
    func resumeKnowledgeSummaryPreservesScalarBoundaries() throws {
        let fixture = try ContextQueryFixture()
        let exactASCII = ProjectResumeKnowledgeEntry(
            compacting: knowledgeEntry(String(repeating: "a", count: 512), fixture: fixture),
            maximumSummaryByteCount: 512)
        let overlongASCII = ProjectResumeKnowledgeEntry(
            compacting: knowledgeEntry(String(repeating: "a", count: 513), fixture: fixture),
            maximumSummaryByteCount: 512)
        let exactScalars = ProjectResumeKnowledgeEntry(
            compacting: knowledgeEntry(String(repeating: "😀", count: 128), fixture: fixture),
            maximumSummaryByteCount: 512)
        let overlongScalars = ProjectResumeKnowledgeEntry(
            compacting: knowledgeEntry("a" + String(repeating: "😀", count: 128), fixture: fixture),
            maximumSummaryByteCount: 512)

        #expect(exactASCII.summary.utf8.count == 512)
        #expect(!exactASCII.summaryIsTruncated)
        #expect(overlongASCII.summary.utf8.count <= 512)
        #expect(overlongASCII.summary.hasSuffix("… [truncated]"))
        #expect(overlongASCII.summaryIsTruncated)
        #expect(exactScalars.summary.utf8.count == 512)
        #expect(!exactScalars.summaryIsTruncated)
        #expect(overlongScalars.summary.utf8.count <= 512)
        #expect(overlongScalars.summary.hasSuffix("… [truncated]"))
        #expect(overlongScalars.summaryIsTruncated)
    }

    @Test("resume maps driver failures and preserves availability failures")
    func resumeMapsFailures() async throws {
        let fixture = try ContextQueryFixture()
        let emptyResume = ProjectResume(project: fixture.project)
        let failingReader = ProjectResumeReaderSpy(resume: emptyResume, failure: .driver)
        await #expect(throws: ContextQueryFailure.readFailed) {
            try await BuildProjectResumeAction(
                workspace: fixture, resumes: failingReader, availability: fixture
            ).perform(ProjectContextRequest())
        }
        let unavailable = ResumeAvailabilityFailure(project: fixture.project)
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await BuildProjectResumeAction(
                workspace: unavailable, resumes: ProjectResumeReaderSpy(resume: emptyResume),
                availability: unavailable
            ).perform(ProjectContextRequest())
        }
    }
}

private func knowledgeEntry(_ summary: String, fixture: ContextQueryFixture) -> KnowledgeEntry {
    KnowledgeEntry(
        id: KnowledgeEntryID(), projectID: fixture.project.projectID, kind: .decision,
        summaryText: summary, source: .session(fixture.session.id),
        sourceContentHash: ContentHash.digest(of: Data(summary.utf8)), createdAt: .distantPast)
}

private struct ResumeAvailabilityFailure: AuthorizedProjectContextReading,
    ContextAvailabilityReading
{
    let project: ProjectContext

    func loadAuthorizedProjectContext() async throws -> ProjectContext { project }
    func loadAvailableGeneration() async throws -> ContextReadGeneration {
        throw ContextQueryFailure.contextUnavailable
    }
}
