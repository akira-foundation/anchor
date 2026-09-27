import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import AnchorSearch
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Persistent project resume")
struct PersistentProjectResumeTests {
    @Test("the persisted resume is complete bounded and project scoped")
    func persistedResumeUsesAllBoundedSelectors() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let seeded = try await seedResume(
            writer: writer, projectID: fixture.observed.projectID,
            otherProjectID: ProjectID.derived(fromSeed: "resume-foreign-project"),
            latestOmittedArtifactAt: 1_200, latestOmittedKnowledgeAt: 1_100)
        try await publish(writer.status)

        let resume = try await fixture.reader().resume.perform(ProjectContextRequest())

        #expect(resume.project.projectID == fixture.observed.projectID)
        #expect(resume.recentSession?.session.id == seeded.sessionID)
        #expect(resume.recentSession?.messageCount == 2)
        #expect(resume.recentSession?.toolActivityCount == 1)
        #expect(resume.lastPresence?.deviceID == seeded.latestDeviceID)
        #expect(resume.currentPlan?.artifact.id == seeded.planID)
        #expect(resume.latestBrainstorm?.artifact.id == seeded.brainstormID)
        #expect(resume.relevantGraphs.count == 3)
        #expect(resume.recentDecisions.count == 5)
        #expect(resume.openTodos.count == 1)
        #expect(resume.openQuestions.count == 1)
        #expect(resume.hasMoreDecisions)
        #expect(!resume.hasMoreTodos)
        #expect(!resume.hasMoreQuestions)
        #expect(resume.lastActivityAt == date(1_200))
        #expect(resume.lastAgentProvider == .codex)
        #expect(resume.recentDecisions.allSatisfy { $0.summary.utf8.count <= 512 })
    }

    @Test("an omitted current knowledge kind still contributes the latest activity")
    func omittedKnowledgeCanSupplyLatestActivity() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        _ = try await seedResume(
            writer: writer, projectID: fixture.observed.projectID,
            otherProjectID: ProjectID.derived(fromSeed: "knowledge-foreign-project"),
            latestOmittedArtifactAt: 800, latestOmittedKnowledgeAt: 1_300)
        try await publish(writer.status)

        let resume = try await fixture.reader().resume.perform(ProjectContextRequest())

        #expect(resume.lastActivityAt == date(1_300))
        #expect(resume.recentDecisions.allSatisfy { $0.kind == .decision })
    }

    @Test("an empty project produces an available empty resume")
    func emptyProjectProducesValidResume() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        _ = try await SQLiteContextSearch(database: writer.database)
        _ = try await SQLiteKnowledgeStore(database: writer.database)
        _ = try await SQLiteDevicePresenceSnapshotStore(database: writer.database)
        try await publish(writer.status)

        let resume = try await fixture.reader().resume.perform(ProjectContextRequest())

        #expect(resume.lastActivityAt == nil)
        #expect(resume.recentSession == nil)
        #expect(resume.lastPresence == nil)
        #expect(resume.currentPlan == nil)
        #expect(resume.latestBrainstorm == nil)
        #expect(resume.relevantGraphs.isEmpty)
        #expect(resume.recentDecisions.isEmpty)
        #expect(resume.openTodos.isEmpty)
        #expect(resume.openQuestions.isEmpty)
    }

    @Test("a generation change refuses the complete resume")
    func generationChangeReturnsContextUnavailable() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        _ = try await SQLiteContextSearch(database: writer.database)
        _ = try await SQLiteKnowledgeStore(database: writer.database)
        _ = try await SQLiteDevicePresenceSnapshotStore(database: writer.database)
        try await publish(writer.status)
        let readers = PersistentContextReaders(
            databaseURL: writer.databaseURL, status: writer.status)
        let changing = ChangingResumeScope(project: projectContext(fixture))

        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await BuildProjectResumeAction(
                workspace: changing, resumes: readers, availability: changing
            ).perform(ProjectContextRequest())
        }
    }

    @Test("a malformed selected knowledge row reports a failed read")
    func malformedKnowledgeReportsReadFailure() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        _ = try await SQLiteContextSearch(database: writer.database)
        let knowledge = try await SQLiteKnowledgeStore(database: writer.database)
        let malformed = knowledgeEntry(
            "malformed-resume", projectID: fixture.observed.projectID,
            kind: .decision, createdAt: 10)
        try await knowledge.recordEntries(
            [malformed],
            supersedingEntriesFrom: .artifact(ArtifactID.derived(fromSeed: "unused")))
        _ = try await SQLiteDevicePresenceSnapshotStore(database: writer.database)
        try await publish(writer.status)
        try await writer.database.run(
            "UPDATE knowledge_entries SET source_content_hash = 'bad' WHERE id = ?;",
            [.text(malformed.id.rawValue)])

        await #expect(throws: ContextQueryFailure.readFailed) {
            try await fixture.reader().resume.perform(ProjectContextRequest())
        }
    }

    private func seedResume(
        writer: ContextReadModelWriter, projectID: ProjectID, otherProjectID: ProjectID,
        latestOmittedArtifactAt: TimeInterval, latestOmittedKnowledgeAt: TimeInterval
    ) async throws -> SeededResumeIdentifiers {
        let plan = try artifactRecord(
            "resume-plan", projectID, .superpowers,
            "docs/superpowers/plans/current.md", revisedAt: 500)
        let brainstorm = try artifactRecord(
            "resume-brainstorm", projectID, .superpowers,
            ".superpowers/brainstorm/current.md", revisedAt: 450)
        let graphs = try (0..<4).map {
            try artifactRecord(
                "resume-graph-\($0)", projectID, .graphify, "graphs/\($0).json",
                revisedAt: 400 - TimeInterval($0))
        }
        let omitted = try artifactRecord(
            "resume-omitted", projectID, .claude, "notes/latest.md",
            revisedAt: latestOmittedArtifactAt)
        let foreign = try artifactRecord(
            "resume-foreign", otherProjectID, .superpowers,
            "docs/superpowers/plans/foreign.md", revisedAt: 2_000)
        try await writer.artifacts.indexArtifactRevisions(
            [plan, brainstorm, omitted, foreign] + graphs)

        let search = try await SQLiteContextSearch(database: writer.database)
        let sessionID = SessionID.derived(fromSeed: "resume-session")
        try await search.indexTranscript(
            transcript(sessionID: sessionID, projectID: projectID, updatedAt: 700))
        try await search.indexTranscript(
            transcript(
                sessionID: SessionID.derived(fromSeed: "foreign-session"),
                projectID: otherProjectID, updatedAt: 3_000))

        let knowledge = try await SQLiteKnowledgeStore(database: writer.database)
        let decisions = (0..<6).map {
            knowledgeEntry(
                "decision-\($0)-" + String(repeating: "x", count: $0 == 0 ? 600 : 0),
                projectID: projectID, kind: .decision,
                createdAt: 900 - TimeInterval($0))
        }
        let todo = knowledgeEntry("todo", projectID: projectID, kind: .todo, createdAt: 850)
        let question = knowledgeEntry(
            "question", projectID: projectID, kind: .question, createdAt: 840)
        let omittedKnowledge = knowledgeEntry(
            "risk", projectID: projectID, kind: .risk,
            createdAt: latestOmittedKnowledgeAt)
        let foreignKnowledge = knowledgeEntry(
            "foreign-decision", projectID: otherProjectID, kind: .decision,
            createdAt: 4_000)
        try await knowledge.recordEntries(
            decisions + [todo, question, omittedKnowledge, foreignKnowledge],
            supersedingEntriesFrom: .artifact(ArtifactID.derived(fromSeed: "resume-unused")))

        let presences = try await SQLiteDevicePresenceSnapshotStore(database: writer.database)
        let olderDeviceID = DeviceID.derived(fromSeed: "resume-older-device")
        let latestDeviceID = DeviceID.derived(fromSeed: "resume-latest-device")
        try await presences.recordPresence(
            DevicePresence(projectID: projectID, deviceID: olderDeviceID, lastSeenAt: date(600)))
        try await presences.recordPresence(
            DevicePresence(projectID: projectID, deviceID: latestDeviceID, lastSeenAt: date(650)))
        try await presences.recordPresence(
            DevicePresence(
                projectID: otherProjectID, deviceID: DeviceID(), lastSeenAt: date(5_000)))

        return SeededResumeIdentifiers(
            sessionID: sessionID, latestDeviceID: latestDeviceID,
            planID: plan.artifact.id, brainstormID: brainstorm.artifact.id)
    }

    private func transcript(
        sessionID: SessionID, projectID: ProjectID, updatedAt: TimeInterval
    ) -> AgentTranscript {
        AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .codex,
                startedAt: date(updatedAt - 10), updatedAt: date(updatedAt)),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID.derived(fromSeed: "\(sessionID.rawValue)-one"),
                        sessionID: sessionID, role: .user, content: "one",
                        timestamp: date(updatedAt - 2))),
                .message(
                    ConversationMessage(
                        id: MessageID.derived(fromSeed: "\(sessionID.rawValue)-two"),
                        sessionID: sessionID, role: .assistant, content: "two",
                        timestamp: date(updatedAt - 1))),
                .toolActivity(
                    ToolActivity(
                        id: ToolActivityID.derived(fromSeed: "\(sessionID.rawValue)-tool"),
                        sessionID: sessionID, toolName: "shell", invocation: "true",
                        outcome: "ok", failed: false, timestamp: date(updatedAt))),
            ])
    }

    private func artifactRecord(
        _ seed: String, _ projectID: ProjectID, _ provider: AgentProvider, _ name: String,
        revisedAt: TimeInterval
    ) throws -> RecordedArtifactRevision {
        let artifact = try #require(
            Artifact(
                id: ArtifactID.derived(fromSeed: seed), projectID: projectID,
                provider: provider, name: name))
        let revision = try #require(
            ArtifactRevision(
                id: RevisionID.derived(fromSeed: "\(seed)-revision"),
                artifactID: artifact.id, parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data(seed.utf8)), deviceID: DeviceID(),
                createdAt: date(revisedAt), retention: artifact.retention))
        return RecordedArtifactRevision(artifact: artifact, revision: revision)
    }

    private func knowledgeEntry(
        _ summary: String, projectID: ProjectID, kind: KnowledgeEntryKind,
        createdAt: TimeInterval
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: KnowledgeEntryID.derived(fromSeed: summary), projectID: projectID, kind: kind,
            summaryText: summary,
            source: .artifact(ArtifactID.derived(fromSeed: "\(summary)-source")),
            sourceContentHash: ContentHash.digest(of: Data(summary.utf8)), origin: .marked,
            createdAt: date(createdAt))
    }

    private func publish(_ status: ContextReadModelStatusStore) async throws {
        let update = try await status.beginUpdate(rebuilding: true)
        try await status.completeUpdate(update, succeeded: true)
    }

    private func projectContext(_ fixture: ContextAssemblyFixture) -> ProjectContext {
        ProjectContext(
            projectID: fixture.observed.projectID, displayName: fixture.observed.projectName,
            canonicalRepositoryRemote: nil, workspaceURL: fixture.observed.workspaceURL)
    }

    private func date(_ secondsSinceEpoch: TimeInterval) -> Date {
        Date(timeIntervalSince1970: secondsSinceEpoch)
    }
}

private struct SeededResumeIdentifiers {
    let sessionID: SessionID
    let latestDeviceID: DeviceID
    let planID: ArtifactID
    let brainstormID: ArtifactID
}

private actor ChangingResumeScope: AuthorizedProjectContextReading, ContextAvailabilityReading {
    let project: ProjectContext
    private var reads = 0

    init(project: ProjectContext) { self.project = project }

    func loadAuthorizedProjectContext() async throws -> ProjectContext { project }

    func loadAvailableGeneration() async throws -> ContextReadGeneration {
        reads += 1
        return ContextReadGeneration(
            identifier: UUID(
                uuidString: reads == 1
                    ? "00000000-0000-0000-0000-000000000001"
                    : "00000000-0000-0000-0000-000000000002")!)
    }
}
