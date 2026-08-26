import Foundation
import Testing

@testable import AnchorDomain

@Suite("Content hash digest")
struct ContentHashDigestTests {
    @Test("the digest of empty content matches the published SHA-256 vector")
    func theDigestOfEmptyContentMatchesThePublishedVector() {
        let digest = ContentHash.digest(of: Data())

        #expect(
            digest.rawValue == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("the digest of abc matches the published SHA-256 vector")
    func theDigestOfAbcMatchesThePublishedVector() {
        let digest = ContentHash.digest(of: Data("abc".utf8))

        #expect(
            digest.rawValue == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("the same content always produces the same digest")
    func theSameContentAlwaysProducesTheSameDigest() {
        let content = Data("skills/commit-guard/SKILL.md".utf8)

        #expect(ContentHash.digest(of: content) == ContentHash.digest(of: content))
    }

    @Test("content that differs by one byte produces a different digest")
    func contentThatDiffersByOneByteProducesADifferentDigest() {
        #expect(
            ContentHash.digest(of: Data("anchor".utf8))
                != ContentHash.digest(of: Data("anchoR".utf8)))
    }

    @Test("a computed digest satisfies the validation the type already enforced")
    func aComputedDigestSatisfiesTheValidationTheTypeAlreadyEnforced() throws {
        let digest = ContentHash.digest(of: Data("anything".utf8))
        let reconstructed = try #require(ContentHash(rawValue: digest.rawValue))

        #expect(reconstructed == digest)
        #expect(digest.rawValue.count == ContentHash.expectedDigestLength)
    }
}
