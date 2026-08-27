import AnchorDomain
import AnchorProvider
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Superpowers classification")
struct SuperpowersClassificationTests {
    private let projectID = ProjectID()

    private func classifyOnly(_ files: [String: String]) async throws -> [KnowledgeEntry] {
        let provider = SuperpowersArtifactProvider(workspaceURL: try WorkspaceFixture.make(files))
        var entries: [KnowledgeEntry] = []
        for discovered in try await provider.discoverArtifacts(forProject: projectID) {
            entries += try await provider.classifyKnowledgeEntries(in: discovered)
        }

        return entries
    }

    @Test("a branch review is a risk, because that is what a review exists to raise")
    func aBranchReviewIsARisk() async throws {
        let entries = try await classifyOnly([
            ".superpowers/sdd/branch-review-abc1234.md": "# Review\nbody"
        ])

        #expect(entries.first?.kind == .risk)
    }

    @Test("a spec is an architecture decision")
    func aSpecIsAnArchitectureDecision() async throws {
        let entries = try await classifyOnly([
            "docs/superpowers/specs/01-scaffold.md": "# Scaffold\nbody"
        ])

        #expect(entries.first?.kind == .architecture)
    }

    @Test(
        "what the folder cannot vouch for stays a summary",
        arguments: ["docs/superpowers/plans/00-indice.md", ".superpowers/brainstorm/idea.md"]
    )
    func whatTheFolderCannotVouchForStaysASummary(_ relativePath: String) async throws {
        let entries = try await classifyOnly([relativePath: "# Title\nbody"])

        #expect(entries.first?.kind == .summary)
    }

    @Test("the summary text is the first line of the file, which is the source speaking")
    func theSummaryTextIsTheFirstLineOfTheFile() async throws {
        let entries = try await classifyOnly([
            "docs/superpowers/plans/04-identity.md":
                "# Fase 04 — Identidade de projeto\n\nEstado: concluída."
        ])

        #expect(entries.first?.summaryText == "# Fase 04 — Identidade de projeto")
    }

    @Test("an empty file yields no knowledge rather than an empty claim")
    func anEmptyFileYieldsNoKnowledge() async throws {
        let entries = try await classifyOnly(["docs/superpowers/plans/empty.md": ""])

        #expect(entries.isEmpty)
    }

    @Test("the entry points back at the artifact it came from")
    func theEntryPointsBackAtTheArtifactItCameFrom() async throws {
        let provider = SuperpowersArtifactProvider(
            workspaceURL: try WorkspaceFixture.make([
                ".superpowers/sdd/design-review.md": "# Design review\nbody"
            ])
        )
        let discovered = try #require(
            try await provider.discoverArtifacts(forProject: projectID).first)

        let entry = try #require(try await provider.classifyKnowledgeEntries(in: discovered).first)

        #expect(entry.source == .artifact(discovered.artifact.id))
        #expect(entry.projectID == projectID)
    }
}
