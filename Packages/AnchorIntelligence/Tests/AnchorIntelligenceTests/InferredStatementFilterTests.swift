import Foundation
import Testing

@testable import AnchorIntelligence

@Suite("What a model said that the caller can actually use")
struct InferredStatementFilterTests {
    private let kinds = ["decision", "todo", "risk"]

    @Test("a statement of a kind that was asked for is kept")
    func statementOfKindThatWasAskedForIsKept() {
        let kept = InferredStatement.usable(
            among: [InferredStatement(kind: "decision", summaryText: "keep the journal local")],
            amongKinds: kinds)

        #expect(kept.map(\.kind) == ["decision"])
    }

    @Test("a kind the model invented is dropped rather than stored")
    func kindModelInventedIsDroppedRatherThanStored() {
        let kept = InferredStatement.usable(
            among: [
                InferredStatement(kind: "epiphany", summaryText: "something"),
                InferredStatement(kind: "todo", summaryText: "wire the search"),
            ],
            amongKinds: kinds)

        #expect(kept.map(\.kind) == ["todo"])
    }

    @Test("a kind spelled with different case is still that kind")
    func kindSpelledWithDifferentCaseIsStillThatKind() {
        let kept = InferredStatement.usable(
            among: [InferredStatement(kind: "DECISION", summaryText: "keep it local")],
            amongKinds: kinds)

        #expect(kept.map(\.kind) == ["decision"])
    }

    @Test("a statement with nothing to say is dropped")
    func statementWithNothingToSayIsDropped() {
        let kept = InferredStatement.usable(
            among: [
                InferredStatement(kind: "todo", summaryText: "   "),
                InferredStatement(kind: "risk", summaryText: "the journal grows unbounded"),
            ],
            amongKinds: kinds)

        #expect(kept.map(\.summaryText) == ["the journal grows unbounded"])
    }

    @Test("the same statement said twice is stored once")
    func sameStatementSaidTwiceIsStoredOnce() {
        let repeated = InferredStatement(kind: "todo", summaryText: "wire the search")
        let kept = InferredStatement.usable(among: [repeated, repeated], amongKinds: kinds)

        #expect(kept.count == 1)
    }
}
