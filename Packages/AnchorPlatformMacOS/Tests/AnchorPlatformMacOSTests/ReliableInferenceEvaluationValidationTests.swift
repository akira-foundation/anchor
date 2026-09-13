import AnchorDomain
import AnchorIntelligence
import AnchorKnowledge
import Testing

@Suite("Validating reliable inference corpus labels")
struct ReliableInferenceEvaluationValidationTests {
    @Test("negative evidence omitted from the model window cannot satisfy coverage")
    func omittedNegativeEvidenceCannotSatisfyCoverage() throws {
        let availableID = MessageID()
        let omittedID = MessageID()
        let unit = try #require(
            AuthorizedConversationUnit(
                fragmentsByMessageID: [availableID: "Run the tests now."], messageIDs: [availableID]
            ))
        let window = AuthorizedInferenceWindow(units: [unit], characterBudget: 3000)

        #expect(throws: EvaluationFailure.self) {
            try requireForbiddenEvidenceInWindow([availableID, omittedID], in: window)
        }
        try requireForbiddenEvidenceInWindow([availableID], in: window)
    }

    @Test("negative coverage is read from explicit negative fixture categories")
    func negativeCoverageIsReadFromExplicitNegativeFixtureCategories() {
        let forbiddenID = MessageID()
        let expectations = CoverageCategory.allCases.map { coverageCategory in
            ExpectedKnowledge(
                kind: .decision,
                coverageCategory: coverageCategory,
                supportingMessageIDs: [MessageID()])
        }
        let evaluationSession = EvaluationSession(
            provider: .codex,
            transcriptPath: "unused",
            expectedKnowledge: expectations,
            forbiddenMessageIDs: [forbiddenID],
            negativeCoverageCategories: [.decision])

        #expect(throws: EvaluationFailure.self) {
            try requireCoverage(in: [evaluationSession])
        }
    }

    @Test("negative categories require forbidden evidence in the same fixture")
    func negativeCategoriesRequireForbiddenEvidenceInSameFixture() {
        let expectations = CoverageCategory.allCases.map { coverageCategory in
            ExpectedKnowledge(
                kind: .decision,
                coverageCategory: coverageCategory,
                supportingMessageIDs: [MessageID()])
        }
        let evaluationSession = EvaluationSession(
            provider: .codex,
            transcriptPath: "unused",
            expectedKnowledge: expectations,
            forbiddenMessageIDs: [],
            negativeCoverageCategories: Set(CoverageCategory.allCases))

        #expect(throws: EvaluationFailure.self) {
            try requireCoverage(in: [evaluationSession])
        }
    }

    @Test("expected support must equal one complete authorized unit")
    func expectedSupportMustEqualOneCompleteAuthorizedUnit() throws {
        let proposalID = MessageID()
        let confirmationID = MessageID()
        let authorizedUnit = try #require(
            AuthorizedConversationUnit(
                fragmentsByMessageID: [
                    proposalID: "proposal",
                    confirmationID: "confirmation",
                ],
                messageIDs: [proposalID, confirmationID]))
        let authorizedWindow = AuthorizedInferenceWindow(
            units: [authorizedUnit],
            characterBudget: InferenceWindow.defaultCharacterBudget)
        let incompleteExpectation = ExpectedKnowledge(
            kind: .decision,
            coverageCategory: .decision,
            supportingMessageIDs: [proposalID])
        let completeExpectation = ExpectedKnowledge(
            kind: .decision,
            coverageCategory: .decision,
            supportingMessageIDs: [proposalID, confirmationID])

        #expect(
            !expectedSupportsMatchCompleteAuthorizedUnits(
                [incompleteExpectation], in: authorizedWindow))
        #expect(
            expectedSupportsMatchCompleteAuthorizedUnits(
                [completeExpectation], in: authorizedWindow))
    }
}
