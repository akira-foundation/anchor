import Foundation
import Testing

@testable import AnchorDomain

@Suite("How an agent session is named as an artifact")
struct AgentSessionArtifactNamingTests {
    private let projectID = ProjectID()
    private let sessionID = SessionID()

    @Test("a session is named under its provider so two providers never collide")
    func sessionIsNamedUnderItsProviderSoTwoProvidersNeverCollide() {
        let claude = AgentSessionArtifactNaming.name(forSession: sessionID, provider: .claude)
        let codex = AgentSessionArtifactNaming.name(forSession: sessionID, provider: .codex)

        #expect(claude != codex)
        #expect(claude.hasPrefix("sessions/claude/"))
        #expect(codex.hasPrefix("sessions/codex/"))
    }

    @Test("an artifact named for a session is recognised as one")
    func artifactNamedForSessionIsRecognisedAsOne() throws {
        let artifact = try #require(
            Artifact(
                id: ArtifactID(),
                projectID: projectID,
                provider: .claude,
                name: AgentSessionArtifactNaming.name(forSession: sessionID, provider: .claude)
            ))

        #expect(artifact.isAgentSessionTranscript)
    }

    @Test("an artifact that is a plan is not a session")
    func artifactThatIsPlanIsNotSession() throws {
        let artifact = try #require(
            Artifact(
                id: ArtifactID(),
                projectID: projectID,
                provider: .superpowers,
                name: "docs/superpowers/plans/00-indice.md"
            ))

        #expect(!artifact.isAgentSessionTranscript)
    }

    @Test("an artifact whose name merely mentions sessions is not a session")
    func artifactWhoseNameMerelyMentionsSessionsIsNotSession() throws {
        let artifact = try #require(
            Artifact(
                id: ArtifactID(),
                projectID: projectID,
                provider: .superpowers,
                name: "docs/sessions-notes.md"
            ))

        #expect(!artifact.isAgentSessionTranscript)
    }
}
