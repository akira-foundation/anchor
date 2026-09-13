import Testing

@testable import AnchorIntelligence

struct ExplicitHarmCandidateTests {
    @Test func harmBeforeQuotedSafeguardRemainsAVerificationCandidate() {
        let claim = """
            Without an upper size limit, cached attachments could exhaust device storage, so keep this rule:
            > Always enforce a size limit.
            """
        let candidates = OnDeviceStatementInference.explicitHarmCandidates(in: claim)

        #expect(candidates.contains(claim))
        #expect(candidates.contains("Always enforce a size limit."))
        #expect(
            candidates.contains { candidate in
                OnDeviceStatementInference.isVerifiedExplicitHarm(
                    ExplicitHarmTag(
                        presence: .present, harmfulOutcomeText: "exhaust device storage",
                        possibilityOrFailureText: "could"), in: candidate)
            })
    }

    @Test func unmarkedQuoteContinuationRemainsInCompleteClaim() {
        let claim = """
            > Without an upper size limit, cached attachments could
            exhaust device storage.
            """
        let candidates = OnDeviceStatementInference.explicitHarmCandidates(in: claim)

        #expect(candidates.contains(claim))
        #expect(
            candidates.contains { candidate in
                OnDeviceStatementInference.isVerifiedExplicitHarm(
                    ExplicitHarmTag(
                        presence: .present, harmfulOutcomeText: "exhaust device storage",
                        possibilityOrFailureText: "could"), in: candidate)
            })
    }

    @Test func unquotedClaimProducesOnlyItsLiteralText() {
        let claim = "Cached attachments could exhaust device storage."
        #expect(OnDeviceStatementInference.explicitHarmCandidates(in: claim) == [claim])
    }

    @Test func safeguardCandidatesCannotSupportInventedHarm() {
        let claim = """
            Revised policy:
            > Ask before each major release.
            > Never publish automatically.
            """
        let candidates = OnDeviceStatementInference.explicitHarmCandidates(in: claim)

        #expect(candidates.contains("Ask before each major release."))
        #expect(candidates.contains("Never publish automatically."))
        #expect(
            candidates.allSatisfy { candidate in
                !OnDeviceStatementInference.isVerifiedExplicitHarm(
                    ExplicitHarmTag(
                        presence: .present, harmfulOutcomeText: "lose stored attachments",
                        possibilityOrFailureText: "could"), in: candidate)
            })
    }
}
