import Foundation
import Testing

@testable import AnchorDomain

@Suite("ContentHash")
struct ContentHashTests {
    private static let validDigest = String(repeating: "a1b2c3d4", count: 8)

    @Test("a well formed digest preserves its raw value")
    func wellFormedDigestPreservesItsRawValue() throws {
        let contentHash = try #require(ContentHash(rawValue: Self.validDigest))

        #expect(contentHash.rawValue == Self.validDigest)
    }

    @Test("a digest shorter than sixty four characters is rejected")
    func digestShorterThanSixtyFourCharactersIsRejected() {
        #expect(ContentHash(rawValue: String(repeating: "a", count: 63)) == nil)
    }

    @Test("a digest longer than sixty four characters is rejected")
    func digestLongerThanSixtyFourCharactersIsRejected() {
        #expect(ContentHash(rawValue: String(repeating: "a", count: 65)) == nil)
    }

    @Test("a digest containing a non hexadecimal character is rejected")
    func digestContainingANonHexadecimalCharacterIsRejected() {
        #expect(ContentHash(rawValue: String(repeating: "a", count: 63) + "z") == nil)
    }

    @Test("an uppercase digest is rejected so that equality stays case exact")
    func uppercaseDigestIsRejectedSoThatEqualityStaysCaseExact() {
        #expect(ContentHash(rawValue: String(repeating: "A", count: 64)) == nil)
    }

    @Test("an empty digest is rejected")
    func emptyDigestIsRejected() {
        #expect(ContentHash(rawValue: "") == nil)
    }
}

@Suite("ContentHash hostile input")
struct ContentHashHostileInputTests {
    @Test("a digest of non ASCII characters that Unicode calls hexadecimal is rejected")
    func digestOfNonASCIICharactersThatUnicodeCallsHexadecimalIsRejected() {
        #expect(ContentHash(rawValue: String(repeating: "\u{FF41}", count: 64)) == nil)
        #expect(ContentHash(rawValue: String(repeating: "\u{FF10}", count: 64)) == nil)
    }

    @Test("a digest is rejected on decoding as well as on construction")
    func digestIsRejectedOnDecodingAsWellAsOnConstruction() throws {
        let hostileRawValue = String(repeating: "\u{FF41}", count: 64)
        let encodedDigest = try JSONEncoder().encode(hostileRawValue)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ContentHash.self, from: encodedDigest)
        }
    }

    @Test("a valid digest survives an encode and decode round trip")
    func validDigestSurvivesAnEncodeAndDecodeRoundTrip() throws {
        let contentHash = try #require(ContentHash(rawValue: String(repeating: "a1b2c3d4", count: 8)))

        let encodedDigest = try JSONEncoder().encode(contentHash)
        let decodedDigest = try JSONDecoder().decode(ContentHash.self, from: encodedDigest)

        #expect(decodedDigest == contentHash)
    }
}
