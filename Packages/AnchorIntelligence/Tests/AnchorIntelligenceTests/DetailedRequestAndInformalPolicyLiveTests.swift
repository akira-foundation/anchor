import AnchorDomain
import AnchorIntelligence
import Foundation
import Testing

@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["ANCHOR_INFERENCE_TESTS"] != nil), .serialized)
struct DetailedRequestAndInformalPolicyLiveTests {
    @Test(arguments: [
        (
            """
            Na aplicação de agenda, a última alteração adicionou uma biblioteca de calendários ao manifesto, mas não atualizou o ficheiro de versões fixas. A instalação falha porque essa biblioteca não consta desse ficheiro.
            Isto impede todos os testes de calendários de arrancar, pois não encontram a classe do cliente. Bloqueia a suite local.
            Fix: atualizar o ficheiro de versões fixas para incluir a biblioteca, confirmar que os testes de calendários correm sem esse erro e commitar o ficheiro atualizado. Confirma primeiro se essa biblioteca é apenas de testes antes de decidir o alcance da atualização.
            """, "none"
        ),
        (
            "ok, mas vc vai trabalhar em paralelo com todos os revisores disponiveis, e nunca em um documento soh\n\n",
            "decision"
        ),
        (
            "The calendar tests cannot start because the dependency lockfile is stale. Update it and run the tests now. From now on, always require independent review before merging any change.",
            "decision"
        ),
    ])
    func separatesImmediateRepairFromOngoingPolicy(_ example: (String, String)) async throws {
        let reference = try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID()], evidenceText: example.0))
        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(over: example.0, keeping: 3000),
                kinds: KnowledgeEntryKind.allCases.map(\.rawValue), evidenceReferences: [reference])
        )
        #expect(statements.map(\.kind) == (example.1 == "none" ? [] : [example.1]))
        #expect(statements.allSatisfy { $0.supportingMessageIDs == reference.supportingMessageIDs })
        #expect(statements.allSatisfy { $0.evidenceText == example.0 })
    }
}
