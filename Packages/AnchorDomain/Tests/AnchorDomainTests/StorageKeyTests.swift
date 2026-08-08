import Foundation
import Testing

@testable import AnchorDomain

@Suite("StorageKey")
struct StorageKeyTests {
    @Test("a well formed key preserves its raw value")
    func wellFormedKeyPreservesItsRawValue() throws {
        let storageKey = try #require(StorageKey(rawValue: "projects/anchor/artifacts/index"))

        #expect(storageKey.rawValue == "projects/anchor/artifacts/index")
    }

    @Test("an empty key is rejected")
    func emptyKeyIsRejected() {
        #expect(StorageKey(rawValue: "") == nil)
    }

    @Test("a key of only whitespace is rejected")
    func keyOfOnlyWhitespaceIsRejected() {
        #expect(StorageKey(rawValue: "   ") == nil)
    }

    @Test(
        "a key containing a parent directory segment is rejected",
        arguments: [
            "../escaped", "projects/../../escaped", "projects/..", "..", "projects/../artifacts",
        ]
    )
    func keyContainingAParentDirectorySegmentIsRejected(_ rawValue: String) {
        #expect(StorageKey(rawValue: rawValue) == nil)
    }

    @Test("a key with a segment that merely starts with dots is accepted")
    func keyWithASegmentThatMerelyStartsWithDotsIsAccepted() throws {
        let storageKey = try #require(StorageKey(rawValue: "projects/..hidden/index"))

        #expect(storageKey.rawValue == "projects/..hidden/index")
    }

    @Test("a key with a leading slash is rejected")
    func keyWithALeadingSlashIsRejected() {
        #expect(StorageKey(rawValue: "/projects/anchor") == nil)
    }
}

@Suite("StorageKey hostile input")
struct StorageKeyHostileInputTests {
    @Test(
        "a key that is rejected on construction is also rejected on decoding",
        arguments: [
            "../escaped", "/absolute", " /etc/passwd", ".", "./secret", "a//b", "", "back\\slash",
            "%2e%2e/x",
        ]
    )
    func keyRejectedOnConstructionIsAlsoRejectedOnDecoding(_ rawValue: String) throws {
        #expect(StorageKey(rawValue: rawValue) == nil)

        let encodedKey = try JSONEncoder().encode(rawValue)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(StorageKey.self, from: encodedKey)
        }
    }

    @Test("a key whose leading whitespace hides an absolute path is rejected")
    func keyWhoseLeadingWhitespaceHidesAnAbsolutePathIsRejected() {
        #expect(StorageKey(rawValue: " /etc/passwd") == nil)
        #expect(StorageKey(rawValue: "\t/etc/passwd") == nil)
    }

    @Test("a current directory segment is rejected")
    func currentDirectorySegmentIsRejected() {
        #expect(StorageKey(rawValue: ".") == nil)
        #expect(StorageKey(rawValue: "./secret") == nil)
        #expect(StorageKey(rawValue: "projects/./index") == nil)
    }

    @Test("an empty segment is rejected so that one object has one key")
    func emptySegmentIsRejectedSoThatOneObjectHasOneKey() {
        #expect(StorageKey(rawValue: "projects//index") == nil)
        #expect(StorageKey(rawValue: "projects/index/") == nil)
    }

    @Test("a backslash is rejected because some providers treat it as a separator")
    func backslashIsRejectedBecauseSomeProvidersTreatItAsASeparator() {
        #expect(StorageKey(rawValue: "..\\..\\etc") == nil)
        #expect(StorageKey(rawValue: "C:\\Windows") == nil)
    }

    @Test("a percent sign is rejected so that encoded traversal cannot be smuggled in")
    func percentSignIsRejectedSoThatEncodedTraversalCannotBeSmuggledIn() {
        #expect(StorageKey(rawValue: "%2e%2e/escaped") == nil)
        #expect(StorageKey(rawValue: "..%2fescaped") == nil)
    }

    @Test("a control character or zero width character is rejected")
    func controlCharacterOrZeroWidthCharacterIsRejected() {
        #expect(StorageKey(rawValue: "a\u{0000}../b") == nil)
        #expect(StorageKey(rawValue: "projects/..\u{200B}/x") == nil)
    }

    @Test("a key longer than the maximum length is rejected")
    func keyLongerThanTheMaximumLengthIsRejected() throws {
        #expect(
            try #require(
                StorageKey(rawValue: String(repeating: "a", count: StorageKey.maximumLength)))
                != nil)
        #expect(
            StorageKey(rawValue: String(repeating: "a", count: StorageKey.maximumLength + 1)) == nil
        )
    }
}
