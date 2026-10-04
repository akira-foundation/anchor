import Testing

@MainActor
struct AnchorMacStatusPresentationTests {
    @Test func watchingSeparatesCapabilities() {
        let presentation = AnchorMacStatusPresentation(
            state: .watching(
                projectName: "Anchor", storage: .synchronized, indexedSessions: 99,
                inferenceStatus: .ready, refusals: []))
        #expect(presentation.projectName == "Anchor")
        #expect(presentation.statusText == "Watching")
        #expect(presentation.rows.map(\.title) == ["iCloud", "Search", "Knowledge"])
        #expect(
            presentation.rows.map(\.statusText) == [
                "Available", "99 sessions searchable", "Inference enabled",
            ])
        #expect(presentation.diagnosticText == nil)
    }

    @Test func unavailableCapabilitiesRemainVisible() {
        let presentation = AnchorMacStatusPresentation(
            state: .watching(
                projectName: "Offline project", storage: .localOnlyUntilAccountReturns,
                indexedSessions: nil, inferenceStatus: .unavailable("Model unavailable"),
                refusals: ["First refusal", "Latest refusal"]))
        #expect(
            presentation.rows.map(\.statusText) == ["Local only", "Unavailable", "Unavailable"])
        #expect(presentation.guidanceText != nil)
        #expect(presentation.diagnosticText?.contains("Latest refusal") == true)
        #expect(presentation.diagnosticText?.contains("Model unavailable") == true)
    }

    @Test func startupAndMissingWorkspaceDoNotClaimHealthyCapabilities() {
        let states: [AnchorMacContextEngine.State] = [.idle, .noWorkspaceConfigured]
        for state in states {
            let presentation = AnchorMacStatusPresentation(state: state)
            #expect(presentation.projectName == nil)
            #expect(presentation.rows.isEmpty)
            #expect(presentation.guidanceText != nil)
        }
    }

    @Test func stoppedEngineKeepsDiagnosticOutOfSummary() {
        let presentation = AnchorMacStatusPresentation(state: .failed("SQLite /private/path"))
        #expect(presentation.statusText == "Stopped")
        #expect(presentation.guidanceText != nil)
        #expect(presentation.diagnosticText == "SQLite /private/path")
        #expect(!presentation.statusText.contains("/private"))
    }

    @Test func disabledInferenceIsNotPresentedAsFailure() {
        let presentation = AnchorMacStatusPresentation(
            state: .watching(
                projectName: "Anchor", storage: .synchronized, indexedSessions: 0,
                inferenceStatus: .disabled, refusals: []))
        #expect(presentation.rows.last?.statusText == "Disabled")
        #expect(presentation.guidanceText == nil)
    }
}
