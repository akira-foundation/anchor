import Foundation
import Testing

@testable import AnchorIntelligence

@Suite("How much of a conversation one question can carry")
struct InferenceWindowTests {
    private func text(ofLength length: Int) -> String {
        String(repeating: "a", count: length)
    }

    @Test("the default window leaves capacity for structured generation")
    func defaultWindowLeavesCapacityForStructuredGeneration() {
        let conversation = text(ofLength: 4_000)

        let window = InferenceWindow(
            over: conversation, keeping: InferenceWindow.defaultCharacterBudget)

        #expect(window.text.count == 3_000)
        #expect(window.omittedCharacterCount == 1_000)
    }

    @Test("a conversation that fits is asked about whole")
    func conversationThatFitsIsAskedAboutWhole() {
        let window = InferenceWindow(over: text(ofLength: 100), keeping: 1_000)

        #expect(window.text.count == 100)
        #expect(window.omittedCharacterCount == 0)
        #expect(!window.wasShortened)
    }

    @Test("a conversation that does not fit says how much was left out")
    func conversationThatDoesNotFitSaysHowMuchWasLeftOut() {
        let window = InferenceWindow(over: text(ofLength: 5_000), keeping: 2_000)

        #expect(window.text.count == 2_000)
        #expect(window.omittedCharacterCount == 3_000)
        #expect(window.wasShortened)
    }

    @Test("what is kept is the end of the conversation, which is the recent part")
    func whatIsKeptIsEndOfConversationWhichIsRecentPart() {
        let window = InferenceWindow(over: "oldest\nmiddle\nnewest", keeping: 6)

        #expect(window.text == "newest")
    }

    @Test("an empty conversation carries nothing and says nothing was left out")
    func emptyConversationCarriesNothingAndSaysNothingWasLeftOut() {
        let window = InferenceWindow(over: "", keeping: 1_000)

        #expect(window.text.isEmpty)
        #expect(window.omittedCharacterCount == 0)
    }

    @Test("a window that keeps nothing keeps nothing rather than crashing")
    func windowThatKeepsNothingKeepsNothingRatherThanCrashing() {
        let window = InferenceWindow(over: text(ofLength: 50), keeping: 0)

        #expect(window.text.isEmpty)
        #expect(window.omittedCharacterCount == 50)
    }

    @Test("prebuilt text is retained without being cut again")
    func prebuiltTextIsRetainedWithoutBeingCutAgain() {
        let window = InferenceWindow(
            text: "<message>authorized suffix</message>",
            omittedCharacterCount: 42)

        #expect(window.text == "<message>authorized suffix</message>")
        #expect(window.omittedCharacterCount == 42)
        #expect(window.wasShortened)
    }

    @Test("a negative supplied omission count is normalized to zero")
    func negativeSuppliedOmissionCountIsNormalizedToZero() {
        let window = InferenceWindow(text: "complete", omittedCharacterCount: -1)

        #expect(window.text == "complete")
        #expect(window.omittedCharacterCount == 0)
        #expect(!window.wasShortened)
    }
}
