import AnchorDomain
import AnchorIntelligence
import Foundation
import Testing

@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["ANCHOR_INFERENCE_TESTS"] != nil), .serialized)
struct ApprovedQuotedPolicyLiveTests {
    private let proposal = """
        Entendido. A regra revista seria:

        > Depois de cada alteração importante no esquema da base de dados, perguntar se queres criar uma cópia de segurança.
        > Não perguntar para alterações apenas de comentários.
        > Nunca criar a cópia automaticamente; fazê-lo só depois de autorização explícita.

        Preferes deixar as alterações de comentários fora desta regra?
        """

    @Test func approvalAdoptsTheQuotedStandingPolicy() async throws {
        let statements = try await infer(proposal, confirmation: "sim")
        #expect(Set(statements.map(\.kind)) == ["decision"])
        #expect(statements.allSatisfy { $0.evidenceText == proposal })
    }

    @Test func unapprovedProposalRemainsTentative() async throws {
        #expect(try await infer(proposal, confirmation: nil).isEmpty)
    }

    @Test func approvalOfImmediateWorkRemainsNonPersistent() async throws {
        #expect(try await infer("Posso executar os testes agora?", confirmation: "sim").isEmpty)
    }

    @Test func approvedQuotedExplicitHarmRemainsRisk() async throws {
        let evidence = """
            Approved storage observation:
            > Without an upper size limit, cached attachments could exhaust device storage.
            """
        #expect(try await infer(evidence, confirmation: "sim").map(\.kind) == ["risk"])
    }

    private func infer(
        _ evidence: String, confirmation: String?
    ) async throws -> [InferredStatement] {
        let reference = try #require(
            InferenceEvidenceReference(
                number: 1,
                supportingMessageIDs: confirmation == nil
                    ? [MessageID()] : [MessageID(), MessageID()],
                evidenceText: evidence, confirmationText: confirmation))
        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(over: evidence, keeping: 3000),
                kinds: KnowledgeEntryKind.allCases.map(\.rawValue), evidenceReferences: [reference])
        )
        #expect(statements.allSatisfy { $0.supportingMessageIDs == reference.supportingMessageIDs })
        return statements
    }
}
