import AnchorDomain
import AnchorIntelligence
import Foundation
import Testing

@testable import AnchorKnowledge

private struct StubInference: StatementInferring {
    let ready: InferenceReadiness
    let statements: [InferredStatement]
    let refusal: (any Error)?

    init(
        ready: InferenceReadiness = .ready,
        statements: [InferredStatement] = [],
        refusal: (any Error)? = nil
    ) {
        self.ready = ready
        self.statements = statements
        self.refusal = refusal
    }

    func readiness() async -> InferenceReadiness { ready }

    func inferStatements(for request: InferenceRequest) async throws -> [InferredStatement] {
        if let refusal { throw refusal }

        return statements
    }
}

private struct Refusal: Error {}

private actor RecordingInference: StatementInferring {
    private(set) var asked: InferenceRequest?

    func readiness() async -> InferenceReadiness { .ready }

    func inferStatements(for request: InferenceRequest) async throws -> [InferredStatement] {
        asked = request

        return []
    }
}

@Suite("Knowledge a model read out of a conversation")
struct InferredKnowledgeExtractorTests {
    private let projectID = ProjectID()
    private let sessionID = SessionID()

    private func request(_ text: String) -> KnowledgeExtractionRequest {
        KnowledgeExtractionRequest(
            text: text,
            projectID: projectID,
            source: .session(sessionID),
            sourceContentHash: ContentHash.digest(of: Data(text.utf8)),
            extractedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    @Test("what the model reported becomes what the project knows")
    func whatModelReportedBecomesWhatProjectKnows() async throws {
        let extractor = InferredKnowledgeExtractor(
            inference: StubInference(statements: [
                InferredStatement(kind: "decision", summaryText: "keep the journal local"),
                InferredStatement(kind: "risk", summaryText: "the journal grows unbounded"),
            ]))

        let entries = try await extractor.extractEntries(for: request("a conversation"))

        #expect(entries.map(\.kind) == [.decision, .risk])
        #expect(entries.allSatisfy { $0.source == .session(sessionID) })
        #expect(entries.allSatisfy { $0.projectID == projectID })
        #expect(entries.allSatisfy { $0.origin == .inferred })
    }

    @Test("a machine with no model reports why inference is unavailable")
    func machineWithNoModelReportsWhyInferenceIsUnavailable() async throws {
        let extractor = InferredKnowledgeExtractor(
            inference: StubInference(
                ready: .unavailable("Apple Intelligence is off"),
                statements: [InferredStatement(kind: "decision", summaryText: "never asked")]
            ))

        do {
            _ = try await extractor.extractEntries(for: request("a conversation"))
            Issue.record("expected unavailable inference to be reported")
        } catch {
            #expect(String(describing: error) == "Apple Intelligence is off")
        }
    }

    @Test("a model that refuses says so instead of reporting nothing")
    func modelThatRefusesSaysSoInsteadOfReportingNothing() async throws {
        let extractor = InferredKnowledgeExtractor(
            inference: StubInference(refusal: Refusal()))

        await #expect(throws: Refusal.self) {
            try await extractor.extractEntries(for: request("a conversation"))
        }
    }

    @Test("a statement with nothing to say is not stored as knowledge")
    func statementWithNothingToSayIsNotStoredAsKnowledge() async throws {
        let extractor = InferredKnowledgeExtractor(
            inference: StubInference(statements: [
                InferredStatement(kind: "todo", summaryText: "   "),
                InferredStatement(kind: "risk", summaryText: "the journal grows unbounded"),
            ]))

        let entries = try await extractor.extractEntries(for: request("a conversation"))

        #expect(entries.map(\.kind) == [.risk])
    }

    @Test("the same sentence of two different kinds is two things the project knows")
    func sameSentenceOfTwoDifferentKindsIsTwoThingsProjectKnows() async throws {
        let extractor = InferredKnowledgeExtractor(
            inference: StubInference(statements: [
                InferredStatement(kind: "risk", summaryText: "the journal grows unbounded"),
                InferredStatement(kind: "todo", summaryText: "the journal grows unbounded"),
            ]))

        let entries = try await extractor.extractEntries(for: request("a conversation"))

        #expect(entries.map(\.kind) == [.risk, .todo])
        #expect(Set(entries.map(\.id)).count == 2)
    }

    @Test("the conversation is cut to the budget before it is asked about")
    func conversationIsCutToBudgetBeforeItIsAskedAbout() async throws {
        let inference = RecordingInference()
        let conversation = String(repeating: "a", count: 5_000)

        _ = try await InferredKnowledgeExtractor(inference: inference, characterBudget: 1_200)
            .extractEntries(for: request(conversation))

        let asked = try #require(await inference.asked)

        #expect(asked.window.text.count == 1_200)
        #expect(asked.window.omittedCharacterCount == 3_800)
    }

    @Test("a kind the domain does not have is not stored as one it does")
    func kindDomainDoesNotHaveIsNotStoredAsOneItDoes() async throws {
        let extractor = InferredKnowledgeExtractor(
            inference: StubInference(statements: [
                InferredStatement(kind: "epiphany", summaryText: "something"),
                InferredStatement(kind: "todo", summaryText: "wire the search"),
            ]))

        let entries = try await extractor.extractEntries(for: request("a conversation"))

        #expect(entries.map(\.kind) == [.todo])
    }

    @Test("the same conversation inferred twice gives the same entries")
    func sameConversationInferredTwiceGivesSameEntries() async throws {
        let extractor = InferredKnowledgeExtractor(
            inference: StubInference(statements: [
                InferredStatement(kind: "todo", summaryText: "wire the search")
            ]))
        let asked = request("a conversation")

        let first = try await extractor.extractEntries(for: asked)
        let second = try await extractor.extractEntries(for: asked)

        #expect(first.map(\.id) == second.map(\.id))
    }

    @Test("an inferred entry is not mistaken for one somebody marked")
    func inferredEntryIsNotMistakenForOneSomebodyMarked() async throws {
        let inferred = try await InferredKnowledgeExtractor(
            inference: StubInference(statements: [
                InferredStatement(kind: "todo", summaryText: "wire the search")
            ])
        ).extractEntries(for: request("TODO: wire the search"))

        let marked = try await MarkedKnowledgeExtractor()
            .extractEntries(for: request("TODO: wire the search"))

        #expect(inferred.first?.summaryText == marked.first?.summaryText)
        #expect(inferred.first?.id != marked.first?.id)
    }
}

@Suite("Two ways of reading a conversation, side by side")
struct CompositeKnowledgeExtractorTests {
    private let projectID = ProjectID()
    private let sessionID = SessionID()

    private func request(_ text: String) -> KnowledgeExtractionRequest {
        KnowledgeExtractionRequest(
            text: text,
            projectID: projectID,
            source: .session(sessionID),
            sourceContentHash: ContentHash.digest(of: Data(text.utf8)),
            extractedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    @Test("what was marked and what was inferred both count")
    func whatWasMarkedAndWhatWasInferredBothCount() async throws {
        let entries = try await CompositeKnowledgeExtractor([
            MarkedKnowledgeExtractor(),
            InferredKnowledgeExtractor(
                inference: StubInference(statements: [
                    InferredStatement(kind: "risk", summaryText: "the journal grows unbounded")
                ])),
        ]).extractEntries(for: request("TODO: wire the search"))

        #expect(Set(entries.map(\.kind)) == [.todo, .risk])
    }

    @Test("an extractor that fails is not hidden behind the ones that worked")
    func extractorThatFailsIsNotHiddenBehindOnesThatWorked() async throws {
        do {
            _ = try await CompositeKnowledgeExtractor([
                InferredKnowledgeExtractor(inference: StubInference(refusal: Refusal())),
                MarkedKnowledgeExtractor(),
            ]).extractEntries(for: request("TODO: wire the search"))
            Issue.record("expected the partial extraction to report its refusal")
        } catch let refusal as KnowledgeExtractionRefusal {
            #expect(refusal.extractedEntries.map(\.kind) == [.todo])
            #expect(refusal.descriptions.first?.contains("Refusal") == true)
        }
    }

    @Test("the same thing found twice is stored once")
    func sameThingFoundTwiceIsStoredOnce() async throws {
        let entries = try await CompositeKnowledgeExtractor([
            MarkedKnowledgeExtractor(), MarkedKnowledgeExtractor(),
        ]).extractEntries(for: request("TODO: wire the search"))

        #expect(entries.count == 1)
    }
}
