import AnchorDomain
import Testing

@testable import AnchorKnowledge

@Suite("Evidence-aware inference window")
struct AuthorizedInferenceWindowTests {
    @Test("the newest fitting units retain conversation order")
    func newestFittingUnitsRetainConversationOrder() {
        let oldest = authorizedUserUnit(content: "oldest")
        let middle = authorizedUserUnit(content: "middle")
        let newest = authorizedUserUnit(content: "newest")
        let middleMessageID = middle.messageIDs[0]
        let newestMessageID = newest.messageIDs[0]
        let expectedText = """
            <unit>
            <message id="\(middleMessageID.rawValue)" role="user">
            middle
            </message>
            </unit>
            <unit>
            <message id="\(newestMessageID.rawValue)" role="user">
            newest
            </message>
            </unit>
            """

        let window = AuthorizedInferenceWindow(
            units: [oldest, middle, newest],
            characterBudget: expectedText.count)

        #expect(window.inferenceWindow.text == expectedText)
        #expect(window.inferenceWindow.text.count == expectedText.count)
        #expect(
            window.fragmentsByMessageID == [
                middleMessageID: "middle",
                newestMessageID: "newest",
            ])
        #expect(
            window.unitIndexByMessageID == [
                middleMessageID: 1,
                newestMessageID: 2,
            ])
    }

    @Test("a proposal and its confirmation are never split across the budget")
    func proposalAndConfirmationAreNeverSplitAcrossBudget() {
        let older = authorizedUserUnit(content: "keep this older statement")
        let confirmed = confirmedAssistantUnit(
            proposal: "store only message identifiers", confirmation: "ok")
        let proposalMessageID = confirmed.messageIDs[0]
        let confirmationMessageID = confirmed.messageIDs[1]
        let expectedText = """
            <unit>
            <message id="\(proposalMessageID.rawValue)" role="user">
            store only message identifiers
            </message>
            <message id="\(confirmationMessageID.rawValue)" role="user">
            ok
            </message>
            </unit>
            """

        let window = AuthorizedInferenceWindow(
            units: [older, confirmed], characterBudget: expectedText.count)

        #expect(window.inferenceWindow.text == expectedText)
        #expect(Set(window.fragmentsByMessageID.keys) == Set(confirmed.messageIDs))
        #expect(Set(window.fragmentsByMessageID.keys).isDisjoint(with: older.messageIDs))
        #expect(
            window.unitIndexByMessageID == [
                proposalMessageID: 1,
                confirmationMessageID: 1,
            ])
        #expect(window.messageIDsByUnitIndex == [1: confirmed.messageIDs])
    }

    @Test("message delimiters and identifiers consume the character budget")
    func messageDelimitersAndIdentifiersConsumeCharacterBudget() {
        let newest = authorizedUserUnit(content: "evidence")
        let newestMessageID = newest.messageIDs[0]
        let expectedText = """
            <unit>
            <message id="\(newestMessageID.rawValue)" role="user">
            evidence
            </message>
            </unit>
            """

        let fittingWindow = AuthorizedInferenceWindow(
            units: [newest], characterBudget: expectedText.count)
        let contentOnlyBudgetWindow = AuthorizedInferenceWindow(
            units: [newest], characterBudget: "evidence".count)

        #expect(fittingWindow.inferenceWindow.text == expectedText)
        #expect(contentOnlyBudgetWindow.inferenceWindow.text.isEmpty)
        #expect(contentOnlyBudgetWindow.fragmentsByMessageID.isEmpty)
        #expect(contentOnlyBudgetWindow.inferenceWindow.text.count <= "evidence".count)
    }

    @Test("an oversized newest fragment keeps an explicitly marked suffix as evidence")
    func oversizedNewestFragmentKeepsExplicitlyMarkedSuffixAsEvidence() {
        let content = String(repeating: "a", count: 90) + "0123456789"
        let newest = authorizedUserUnit(content: content)
        let newestMessageID = newest.messageIDs[0]
        let expectedText = """
            <unit>
            <message id="\(newestMessageID.rawValue)" role="user">
            <omitted characters="90"/>0123456789
            </message>
            </unit>
            """

        let window = AuthorizedInferenceWindow(
            units: [newest], characterBudget: expectedText.count)

        #expect(window.inferenceWindow.text == expectedText)
        #expect(window.inferenceWindow.text.count == expectedText.count)
        #expect(window.inferenceWindow.omittedCharacterCount == 90)
        #expect(window.fragmentsByMessageID == [newestMessageID: "0123456789"])
        #expect(window.unitIndexByMessageID == [newestMessageID: 0])
    }

    @Test("an oversized Unicode fragment budgets and retains whole graphemes")
    func oversizedUnicodeFragmentBudgetsAndRetainsWholeGraphemes() {
        let familyGrapheme = "👨‍👩‍👧‍👦"
        let retainedSuffix = "x\(familyGrapheme)y"
        let content = String(repeating: "a", count: 90) + retainedSuffix
        let newest = authorizedUserUnit(content: content)
        let newestMessageID = newest.messageIDs[0]
        let expectedText = """
            <unit>
            <message id="\(newestMessageID.rawValue)" role="user">
            <omitted characters="90"/>x👨‍👩‍👧‍👦y
            </message>
            </unit>
            """
        let exactCharacterBudget = 119

        #expect(expectedText.count == exactCharacterBudget)

        let window = AuthorizedInferenceWindow(
            units: [newest], characterBudget: exactCharacterBudget)

        #expect(window.inferenceWindow.text == expectedText)
        #expect(window.inferenceWindow.text.count <= exactCharacterBudget)
        #expect(window.inferenceWindow.text.contains(newestMessageID.rawValue))
        #expect(window.inferenceWindow.text.hasSuffix("\n</message>\n</unit>"))
        #expect(window.inferenceWindow.omittedCharacterCount == 90)
        #expect(window.fragmentsByMessageID == [newestMessageID: retainedSuffix])
        #expect(window.unitIndexByMessageID == [newestMessageID: 0])
    }

    @Test("an oversized confirmed unit preserves both evidence identifiers")
    func oversizedConfirmedUnitPreservesBothEvidenceIdentifiers() {
        let proposal = String(repeating: "p", count: 92) + "PROPOSAL"
        let confirmed = confirmedAssistantUnit(proposal: proposal, confirmation: "ok")
        let proposalMessageID = confirmed.messageIDs[0]
        let confirmationMessageID = confirmed.messageIDs[1]
        let expectedText = """
            <unit>
            <message id="\(proposalMessageID.rawValue)" role="user">
            <omitted characters="92"/>PROPOSAL
            </message>
            <message id="\(confirmationMessageID.rawValue)" role="user">
            ok
            </message>
            </unit>
            """

        let window = AuthorizedInferenceWindow(
            units: [confirmed], characterBudget: expectedText.count)

        #expect(window.inferenceWindow.text == expectedText)
        #expect(window.inferenceWindow.text.count <= expectedText.count)
        #expect(window.inferenceWindow.omittedCharacterCount == 92)
        #expect(
            window.fragmentsByMessageID == [
                proposalMessageID: "PROPOSAL",
                confirmationMessageID: "ok",
            ])
        #expect(
            window.unitIndexByMessageID == [
                proposalMessageID: 0,
                confirmationMessageID: 0,
            ])
    }

    @Test("selection stops at the first older unit that does not fit")
    func selectionStopsAtFirstOlderUnitThatDoesNotFit() {
        let oldest = authorizedUserUnit(content: "oldest")
        let oversizedMiddle = authorizedUserUnit(
            content: String(repeating: "m", count: 200))
        let newest = authorizedUserUnit(content: "newest")
        let newestMessageID = newest.messageIDs[0]
        let expectedText = """
            <unit>
            <message id="\(newestMessageID.rawValue)" role="user">
            newest
            </message>
            </unit>
            """

        let window = AuthorizedInferenceWindow(
            units: [oldest, oversizedMiddle, newest],
            characterBudget: expectedText.count + 20)

        #expect(window.inferenceWindow.text == expectedText)
        #expect(window.fragmentsByMessageID == [newestMessageID: "newest"])
        #expect(window.unitIndexByMessageID == [newestMessageID: 2])
    }

    @Test("zero and structurally insufficient budgets transmit no partial delimiters")
    func zeroAndStructurallyInsufficientBudgetsTransmitNoPartialDelimiters() {
        let newest = authorizedUserUnit(content: "remember this")

        for characterBudget in [0, 10] {
            let window = AuthorizedInferenceWindow(
                units: [newest], characterBudget: characterBudget)

            #expect(window.inferenceWindow.text.isEmpty)
            #expect(window.inferenceWindow.text.count <= characterBudget)
            #expect(window.fragmentsByMessageID.isEmpty)
            #expect(window.unitIndexByMessageID.isEmpty)
            #expect(window.messageIDsByUnitIndex.isEmpty)
            #expect(window.inferenceWindow.omittedCharacterCount > 0)
        }
    }

    @Test("an empty unit list produces an empty complete window")
    func emptyUnitListProducesEmptyCompleteWindow() {
        let window = AuthorizedInferenceWindow(units: [], characterBudget: 100)

        #expect(window.inferenceWindow.text.isEmpty)
        #expect(window.inferenceWindow.omittedCharacterCount == 0)
        #expect(window.fragmentsByMessageID.isEmpty)
        #expect(window.unitIndexByMessageID.isEmpty)
        #expect(window.messageIDsByUnitIndex.isEmpty)
    }

    private func authorizedUserUnit(content: String) -> AuthorizedConversationUnit {
        let messageID = MessageID.derived(fromSeed: "authorized-user:\(content)")

        return AuthorizedConversationUnit(
            fragmentsByMessageID: [messageID: content],
            messageIDs: [messageID])!
    }

    private func confirmedAssistantUnit(
        proposal: String,
        confirmation: String
    ) -> AuthorizedConversationUnit {
        let proposalMessageID = MessageID.derived(
            fromSeed: "confirmed-proposal:\(proposal)")
        let confirmationMessageID = MessageID.derived(
            fromSeed: "confirmed-reply:\(proposal):\(confirmation)")

        return AuthorizedConversationUnit(
            fragmentsByMessageID: [
                proposalMessageID: proposal,
                confirmationMessageID: confirmation,
            ],
            messageIDs: [proposalMessageID, confirmationMessageID])!
    }
}
