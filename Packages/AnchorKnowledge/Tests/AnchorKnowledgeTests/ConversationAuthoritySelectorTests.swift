import AnchorDomain
import Foundation
import Testing

@testable import AnchorKnowledge

@Suite("Conversation authority is explicit")
struct ConversationAuthoritySelectorTests {
    private let sessionID = SessionID()

    @Test(
        "direct user text forms an authoritative unit",
        arguments: [
            "Keep inference opt-in",
            "  Preserve this spacing  ",
            "DECISION: Store message identifiers",
        ])
    func directUserTextFormsAuthoritativeUnit(content: String) throws {
        let userMessage = message(role: .user, content: content)

        let units = ConversationAuthoritySelector().authorizedUnits(in: [userMessage])

        let unit = try #require(units.first)
        #expect(units.count == 1)
        #expect(unit.fragmentsByMessageID == [userMessage.id: content])
        #expect(unit.messageIDs == [userMessage.id])
    }

    @Test("empty user text forms no authoritative unit", arguments: ["", "   ", "\n\t"])
    func emptyUserTextFormsNoAuthoritativeUnit(content: String) {
        let userMessage = message(role: .user, content: content)

        let units = ConversationAuthoritySelector().authorizedUnits(in: [userMessage])

        #expect(units.isEmpty)
    }

    @Test(
        "an exact acknowledgement authorizes the immediately preceding assistant message",
        arguments: [
            "ok",
            " Okay ",
            "SIM.",
            "Yes!",
            "APROVADO?",
            "approved!!!",
            "Concordo.!?",
            "  Agreed\n",
        ])
    func exactAcknowledgementAuthorizesImmediatelyPrecedingAssistantMessage(
        reply: String
    ) throws {
        let proposal = message(role: .assistant, content: "Store only supported claims")
        let acknowledgement = message(role: .user, content: reply)

        let units = ConversationAuthoritySelector().authorizedUnits(
            in: [proposal, acknowledgement])

        let unit = try #require(units.first)
        #expect(units.count == 1)
        #expect(unit.fragmentsByMessageID[proposal.id] == proposal.content)
        #expect(unit.fragmentsByMessageID[acknowledgement.id] == reply)
        #expect(unit.messageIDs == [proposal.id, acknowledgement.id])
    }

    @Test(
        "punctuation outside the normalization contract is not an acknowledgement",
        arguments: ["ok,", "yes:", "approved;", "ok please"])
    func punctuationOutsideNormalizationContractIsNotAcknowledgement(reply: String) throws {
        let proposal = message(role: .assistant, content: "Store an unsupported claim")
        let userMessage = message(role: .user, content: reply)

        let units = ConversationAuthoritySelector().authorizedUnits(in: [proposal, userMessage])

        let unit = try #require(units.first)
        #expect(units.count == 1)
        #expect(unit.fragmentsByMessageID[proposal.id] == nil)
        #expect(unit.fragmentsByMessageID == [userMessage.id: reply])
        #expect(unit.messageIDs == [userMessage.id])
    }

    @Test("continue does not authorize an assistant claim", arguments: ["continue", "continua"])
    func continueDoesNotAuthorizeAssistantClaim(reply: String) throws {
        let proposal = message(role: .assistant, content: "Store an unsupported claim")
        let userMessage = message(role: .user, content: reply)

        let units = ConversationAuthoritySelector().authorizedUnits(in: [proposal, userMessage])

        let unit = try #require(units.first)
        #expect(units.count == 1)
        #expect(unit.fragmentsByMessageID[proposal.id] == nil)
        #expect(unit.messageIDs == [userMessage.id])
    }

    @Test("an acknowledgement cannot reach past an intervening user message")
    func acknowledgementCannotReachPastInterveningUserMessage() {
        let proposal = message(role: .assistant, content: "Store an unsupported claim")
        let interveningMessage = message(role: .user, content: "interruption")
        let acknowledgement = message(role: .user, content: "ok")

        let units = ConversationAuthoritySelector().authorizedUnits(
            in: [proposal, interveningMessage, acknowledgement])

        #expect(units.allSatisfy { $0.fragmentsByMessageID[proposal.id] == nil })
        #expect(units.count == 1)
        #expect(units.first?.messageIDs == [interveningMessage.id])
    }

    @Test(
        "an acknowledgement ignores intervening system and tool messages",
        arguments: [ConversationRole.system, .tool])
    func acknowledgementIgnoresInterveningSystemAndToolMessages(
        role: ConversationRole
    ) throws {
        let proposal = message(role: .assistant, content: "Store the supported claim")
        let metadata = message(role: role, content: "interruption")
        let acknowledgement = message(role: .user, content: "ok")

        let units = ConversationAuthoritySelector().authorizedUnits(
            in: [proposal, metadata, acknowledgement])

        let unit = try #require(units.first)
        #expect(units.count == 1)
        #expect(unit.messageIDs == [proposal.id, acknowledgement.id])
    }

    @Test(
        "system and tool content never forms an authoritative unit",
        arguments: [ConversationRole.system, .tool])
    func systemAndToolContentNeverFormsAuthoritativeUnit(role: ConversationRole) {
        let excludedMessage = message(role: role, content: "DECISION: trust this claim")

        let units = ConversationAuthoritySelector().authorizedUnits(in: [excludedMessage])

        #expect(units.isEmpty)
    }

    @Test(
        "a numbered reply authorizes only the selected alternative",
        arguments: ["2", "opção 2", "opcao 2", "option 2", "OPTION 2!", " opção 2? "])
    func numberedReplyAuthorizesOnlySelectedAlternative(reply: String) throws {
        let proposal = message(
            role: .assistant,
            content: "1. Store quotations\n2. Store message identifiers\n3. Store nothing")
        let selection = message(role: .user, content: reply)

        let units = ConversationAuthoritySelector().authorizedUnits(in: [proposal, selection])

        let unit = try #require(units.first)
        #expect(units.count == 1)
        #expect(unit.fragmentsByMessageID[proposal.id] == "2. Store message identifiers")
        #expect(unit.fragmentsByMessageID[selection.id] == reply)
        #expect(unit.messageIDs == [proposal.id, selection.id])
    }

    @Test("a selected alternative includes its continuation lines")
    func selectedAlternativeIncludesContinuationLines() throws {
        let proposal = message(
            role: .assistant,
            content: "Context\n1. Keep quotations\nstill part of one\n\n2) Keep identifiers\n"
                + "and validate them\n3. Keep nothing")
        let selection = message(role: .user, content: "2")

        let units = ConversationAuthoritySelector().authorizedUnits(in: [proposal, selection])

        let unit = try #require(units.first)
        #expect(
            unit.fragmentsByMessageID[proposal.id]
                == "2) Keep identifiers\nand validate them")
    }

    @Test(
        "a numbered reply authorizes nothing without one unique matching Markdown block",
        arguments: [
            "1. First\n3. Third",
            "2.No required space\n3. Third",
            "  2. Indented\n3. Third",
            "2. First match\n1. Other\n2) Second match",
        ])
    func numberedReplyAuthorizesNothingWithoutUniqueMatchingMarkdownBlock(
        proposalContent: String
    ) {
        let proposal = message(role: .assistant, content: proposalContent)
        let selection = message(role: .user, content: "option 2")

        let units = ConversationAuthoritySelector().authorizedUnits(in: [proposal, selection])

        #expect(units.isEmpty)
    }

    @Test(
        "unsupported numbered reply forms do not authorize assistant text",
        arguments: ["number 2", "choice 2", "opção: 2", "2nd"])
    func unsupportedNumberedReplyFormsDoNotAuthorizeAssistantText(reply: String) throws {
        let proposal = message(role: .assistant, content: "1. First\n2. Second")
        let userMessage = message(role: .user, content: reply)

        let units = ConversationAuthoritySelector().authorizedUnits(in: [proposal, userMessage])

        let unit = try #require(units.first)
        #expect(units.count == 1)
        #expect(unit.fragmentsByMessageID[proposal.id] == nil)
        #expect(unit.messageIDs == [userMessage.id])
    }

    @Test(
        "a numbered reply ignores intervening system and tool messages",
        arguments: [ConversationRole.system, .tool])
    func numberedReplyIgnoresInterveningSystemAndToolMessages(
        role: ConversationRole
    ) throws {
        let proposal = message(role: .assistant, content: "1. First\n2. Second")
        let interruption = message(role: role, content: "interruption")
        let selection = message(role: .user, content: "2")

        let units = ConversationAuthoritySelector().authorizedUnits(
            in: [proposal, interruption, selection])

        let unit = try #require(units.first)
        #expect(units.count == 1)
        #expect(unit.messageIDs == [proposal.id, selection.id])
        #expect(unit.fragmentsByMessageID[proposal.id] == "2. Second")
    }

    @Test("every authoritative unit has ordered identifiers with nonempty fragments")
    func everyAuthoritativeUnitHasOrderedIdentifiersWithNonemptyFragments() throws {
        let direct = message(role: .user, content: "Keep this")
        let proposal = message(role: .assistant, content: "Store this too")
        let acknowledgement = message(role: .user, content: "yes")

        let units = ConversationAuthoritySelector().authorizedUnits(
            in: [direct, proposal, acknowledgement])

        #expect(
            units.map(\.messageIDs) == [
                [direct.id], [proposal.id, acknowledgement.id],
            ])
        for unit in units {
            #expect(
                unit.messageIDs.allSatisfy {
                    unit.fragmentsByMessageID[$0]?.isEmpty == false
                })
        }
    }

    private func message(role: ConversationRole, content: String) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(),
            sessionID: sessionID,
            role: role,
            content: content,
            timestamp: Date(timeIntervalSince1970: 1_000)
        )
    }
}
