import Foundation
import Testing

@testable import AnchorDomain

@Suite("Canonical repository remote")
struct CanonicalRepositoryRemoteTests {
    @Test(
        "the three remote forms of one repository converge",
        arguments: [
            "git@github.com:akira-io/payable.git",
            "https://github.com/akira-io/payable.git",
            "https://github.com/akira-io/payable",
        ]
    )
    func theThreeRemoteFormsOfOneRepositoryConverge(_ gitRemote: String) throws {
        let remote = try #require(CanonicalRepositoryRemote(gitRemote: gitRemote))

        #expect(remote.rawValue == "github.com/akira-io/payable")
    }

    @Test("normalizing an already canonical value does not change it")
    func normalizingAnAlreadyCanonicalValueDoesNotChangeIt() throws {
        let once = try #require(
            CanonicalRepositoryRemote(gitRemote: "https://github.com/akira-io/payable.git"))
        let twice = try #require(CanonicalRepositoryRemote(gitRemote: once.rawValue))

        #expect(twice == once)
    }

    @Test("the host is compared without regard to letter case")
    func theHostIsComparedWithoutRegardToLetterCase() throws {
        let upperCased = try #require(
            CanonicalRepositoryRemote(gitRemote: "https://GitHub.COM/akira-io/payable"))
        let lowerCased = try #require(
            CanonicalRepositoryRemote(gitRemote: "https://github.com/akira-io/payable"))

        #expect(upperCased == lowerCased)
    }

    @Test("the path keeps its letter case because only DNS guarantees insensitivity")
    func thePathKeepsItsLetterCase() throws {
        let remote = try #require(
            CanonicalRepositoryRemote(gitRemote: "https://github.com/akira-io/Payable"))

        #expect(remote.rawValue == "github.com/akira-io/Payable")
    }

    @Test(
        "a remote without a host is rejected",
        arguments: ["payable", "/akira-io/payable", "https:///akira-io/payable", ""]
    )
    func remoteWithoutAHostIsRejected(_ gitRemote: String) {
        #expect(CanonicalRepositoryRemote(gitRemote: gitRemote) == nil)
    }

    @Test(
        "a remote without a path is rejected",
        arguments: ["https://github.com", "https://github.com/", "git@github.com:"]
    )
    func remoteWithoutAPathIsRejected(_ gitRemote: String) {
        #expect(CanonicalRepositoryRemote(gitRemote: gitRemote) == nil)
    }

    @Test(
        "embedded credentials never reach the canonical value",
        arguments: [
            "https://kid:ghp_secrettoken@github.com/akira-io/payable.git",
            "https://ghp_secrettoken@github.com/akira-io/payable",
            "ssh://git@github.com/akira-io/payable.git",
        ]
    )
    func embeddedCredentialsNeverReachTheCanonicalValue(_ gitRemote: String) throws {
        let remote = try #require(CanonicalRepositoryRemote(gitRemote: gitRemote))

        #expect(remote.rawValue == "github.com/akira-io/payable")
        #expect(!remote.rawValue.contains("ghp_secrettoken"))
        #expect(!remote.rawValue.contains("@"))
    }

    @Test("a host that is not a forge normalizes by form, without a known-host list")
    func aHostThatIsNotAForgeNormalizesByForm() throws {
        let subgroup = try #require(
            CanonicalRepositoryRemote(
                gitRemote: "https://gitlab.example.com/team/subgroup/service.git")
        )
        let selfHosted = try #require(
            CanonicalRepositoryRemote(gitRemote: "git@git.internal:infra/tooling.git"))

        #expect(subgroup.rawValue == "gitlab.example.com/team/subgroup/service")
        #expect(selfHosted.rawValue == "git.internal/infra/tooling")
    }

    @Test("a port is transport and does not belong to the identity")
    func aPortIsTransportAndDoesNotBelongToTheIdentity() throws {
        let ported = try #require(
            CanonicalRepositoryRemote(gitRemote: "ssh://git@git.internal:2222/infra/tooling.git"))

        #expect(ported.rawValue == "git.internal/infra/tooling")
    }

    @Test("the strict initializer accepts only the canonical form")
    func theStrictInitializerAcceptsOnlyTheCanonicalForm() throws {
        let canonical = try #require(
            CanonicalRepositoryRemote(rawValue: "github.com/akira-io/payable"))

        #expect(canonical.rawValue == "github.com/akira-io/payable")
        #expect(CanonicalRepositoryRemote(rawValue: "https://github.com/akira-io/payable") == nil)
        #expect(CanonicalRepositoryRemote(rawValue: "github.com/akira-io/payable.git") == nil)
        #expect(CanonicalRepositoryRemote(rawValue: "GitHub.com/akira-io/payable") == nil)
    }

    @Test("a remote that was never canonical is rejected on decoding")
    func aRemoteThatWasNeverCanonicalIsRejectedOnDecoding() {
        let encoded = Data(#""https://github.com/akira-io/payable""#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CanonicalRepositoryRemote.self, from: encoded)
        }
    }

    @Test("a canonical remote survives an encode and decode round trip")
    func aCanonicalRemoteSurvivesAnEncodeAndDecodeRoundTrip() throws {
        let remote = try #require(
            CanonicalRepositoryRemote(gitRemote: "git@github.com:akira-io/payable.git"))
        let encoded = try JSONEncoder().encode(remote)
        let decoded = try JSONDecoder().decode(CanonicalRepositoryRemote.self, from: encoded)

        #expect(decoded == remote)
    }
}
