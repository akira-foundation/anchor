import Foundation
import Testing

@testable import AnchorFoundation

private enum CodableTestSubject {}

@Suite("Identifier coding")
struct IdentifierCodableTests {
    @Test("an identifier survives an encode and decode round trip")
    func identifierSurvivesAnEncodeAndDecodeRoundTrip() throws {
        let originalIdentifier = Identifier<CodableTestSubject>()

        let encodedIdentifier = try JSONEncoder().encode(originalIdentifier)
        let decodedIdentifier = try JSONDecoder().decode(
            Identifier<CodableTestSubject>.self,
            from: encodedIdentifier
        )

        #expect(decodedIdentifier == originalIdentifier)
    }

    @Test("an identifier encodes as a bare string rather than an object")
    func identifierEncodesAsABareStringRatherThanAnObject() throws {
        let identifier = Identifier<CodableTestSubject>()

        let encodedIdentifier = try JSONEncoder().encode(identifier)

        #expect(String(decoding: encodedIdentifier, as: UTF8.self) == "\"\(identifier.rawValue)\"")
    }

    @Test("decoding rejects a raw value that is not a UUID")
    func decodingRejectsARawValueThatIsNotAUniversallyUniqueIdentifier() {
        let encodedIdentifier = Data("\"not-a-uuid\"".utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Identifier<CodableTestSubject>.self, from: encodedIdentifier)
        }
    }
}

@Suite("Identifier canonicalisation")
struct IdentifierCanonicalisationTests {
    @Test("the same UUID in different letter cases produces equal identifiers")
    func sameUniversallyUniqueIdentifierInDifferentLetterCasesProducesEqualIdentifiers() throws {
        let uppercaseRawValue = "3F2A1B4C-5D6E-4A7B-8C9D-0E1F2A3B4C5D"

        let fromUppercase = try #require(
            Identifier<CodableTestSubject>(rawValue: uppercaseRawValue))
        let fromLowercase = try #require(
            Identifier<CodableTestSubject>(rawValue: uppercaseRawValue.lowercased())
        )

        #expect(fromUppercase == fromLowercase)
        #expect(fromUppercase.hashValue == fromLowercase.hashValue)
    }

    @Test("a lowercase raw value is stored in canonical uppercase form")
    func lowercaseRawValueIsStoredInCanonicalUppercaseForm() throws {
        let identifier = try #require(
            Identifier<CodableTestSubject>(rawValue: "3f2a1b4c-5d6e-4a7b-8c9d-0e1f2a3b4c5d")
        )

        #expect(identifier.rawValue == "3F2A1B4C-5D6E-4A7B-8C9D-0E1F2A3B4C5D")
    }

    @Test("decoding canonicalises the letter case so synced records do not fork")
    func decodingCanonicalisesTheLetterCaseSoSyncedRecordsDoNotFork() throws {
        let lowercaseEncoded = Data("\"3f2a1b4c-5d6e-4a7b-8c9d-0e1f2a3b4c5d\"".utf8)
        let uppercaseEncoded = Data("\"3F2A1B4C-5D6E-4A7B-8C9D-0E1F2A3B4C5D\"".utf8)

        let fromLowercase = try JSONDecoder().decode(
            Identifier<CodableTestSubject>.self, from: lowercaseEncoded)
        let fromUppercase = try JSONDecoder().decode(
            Identifier<CodableTestSubject>.self, from: uppercaseEncoded)

        #expect(fromLowercase == fromUppercase)
    }
}
