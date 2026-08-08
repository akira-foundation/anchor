import Foundation
import Testing

@testable import AnchorFoundation

private enum IdentifierTestSubject {}

@Suite("Identifier")
struct IdentifierTests {
    @Test("two freshly created identifiers are never equal")
    func twoFreshlyCreatedIdentifiersAreNeverEqual() {
        let firstIdentifier = Identifier<IdentifierTestSubject>()
        let secondIdentifier = Identifier<IdentifierTestSubject>()

        #expect(firstIdentifier != secondIdentifier)
    }

    @Test("an identifier restored from its raw value equals the original")
    func identifierRestoredFromRawValueEqualsTheOriginal() throws {
        let originalIdentifier = Identifier<IdentifierTestSubject>()

        let restoredIdentifier = try #require(
            Identifier<IdentifierTestSubject>(rawValue: originalIdentifier.rawValue)
        )

        #expect(restoredIdentifier == originalIdentifier)
    }

    @Test("an identifier rejects a raw value that is not a UUID")
    func identifierRejectsRawValueThatIsNotAUniversallyUniqueIdentifier() {
        #expect(Identifier<IdentifierTestSubject>(rawValue: "not-a-uuid") == nil)
    }
}
