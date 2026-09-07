import AnchorDomain
import Testing

@testable import AnchorKnowledge

enum InvalidAuthorizedUnitShape: CaseIterable, Sendable {
    case emptyUnit
    case messageIDWithoutFragment
    case extraFragmentKey
    case duplicateMessageID
    case emptyFragment
    case whitespaceOnlyFragment
}

@Suite("Authorized conversation unit validation")
struct AuthorizedConversationUnitTests {
    @Test("valid fragments retain their supplied message order")
    func validFragmentsRetainSuppliedMessageOrder() throws {
        let firstMessageID = MessageID()
        let secondMessageID = MessageID()
        let fragmentsByMessageID = [
            firstMessageID: "first fragment",
            secondMessageID: "  second fragment  ",
        ]
        let candidate: AuthorizedConversationUnit? = AuthorizedConversationUnit(
            fragmentsByMessageID: fragmentsByMessageID,
            messageIDs: [secondMessageID, firstMessageID])

        let authorizedUnit = try #require(candidate)

        #expect(authorizedUnit.fragmentsByMessageID == fragmentsByMessageID)
        #expect(authorizedUnit.messageIDs == [secondMessageID, firstMessageID])
    }

    @Test(
        "invalid fragment and message identifier shapes are rejected",
        arguments: InvalidAuthorizedUnitShape.allCases)
    func invalidFragmentAndMessageIdentifierShapesAreRejected(
        shape: InvalidAuthorizedUnitShape
    ) {
        let firstMessageID = MessageID()
        let secondMessageID = MessageID()
        let invalidState: (fragmentsByMessageID: [MessageID: String], messageIDs: [MessageID])

        switch shape {
        case .emptyUnit:
            invalidState = ([:], [])
        case .messageIDWithoutFragment:
            invalidState = ([:], [firstMessageID])
        case .extraFragmentKey:
            invalidState = (
                [firstMessageID: "first", secondMessageID: "second"],
                [firstMessageID]
            )
        case .duplicateMessageID:
            invalidState = ([firstMessageID: "first"], [firstMessageID, firstMessageID])
        case .emptyFragment:
            invalidState = ([firstMessageID: ""], [firstMessageID])
        case .whitespaceOnlyFragment:
            invalidState = ([firstMessageID: " \n\t "], [firstMessageID])
        }

        let candidate: AuthorizedConversationUnit? = AuthorizedConversationUnit(
            fragmentsByMessageID: invalidState.fragmentsByMessageID,
            messageIDs: invalidState.messageIDs)

        #expect(candidate == nil)
    }
}
