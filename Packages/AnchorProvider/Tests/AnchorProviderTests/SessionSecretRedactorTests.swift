import Foundation
import Testing

@testable import AnchorProvider

@Suite("Redacting secrets out of a session transcript")
struct SessionSecretRedactorTests {
    private let redactor = SessionSecretRedactor()

    private static func credentialShapedSample(_ prefix: String, _ body: String) -> String {
        prefix + body
    }

    @Test(
        "each rule masks a value shaped like the secret it names",
        arguments: [
            ("url-credentials", "psql postgresql://appuser:hunter2secret@db.internal/anchor"),
            ("assigned-secret", "GITHUB_TOKEN=abcdefghijklmnopqrstuvwxyz012345"),
            ("assigned-secret", "TEST_PASSWORD = 'correcthorsebatterystaple'"),
            (
                "json-web-token",
                "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r"
            ),
            ("google-key", "AIzaSyA1234567890abcdefghijklmnopqrstuvw"),
            ("stripe-key", Self.credentialShapedSample("sk_live", "_51HxxxxxxxxxxxxxxxxxxxxxxZZ")),
            ("anthropic-key", "sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAA"),
            ("openai-key", "sk-proj-AAAAAAAAAAAAAAAAAAAAAAAABBBB"),
            (
                "github-token",
                Self.credentialShapedSample("ghp", "_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
            ),
            ("slack-token", Self.credentialShapedSample("xoxb", "-1234567890-ABCDEFGHIJ")),
            ("aws-access-key", Self.credentialShapedSample("AKIA", "IOSFODNN7EXAMPLE")),
        ]
    )
    func eachRuleMasksAValueShapedLikeTheSecretItNames(ruleName: String, text: String) {
        let redacted = redactor.redact(text)

        #expect(redacted.contains(SessionSecretRedactor.marker(for: ruleName)))
    }

    @Test(
        "a name that merely describes a secret is not treated as one",
        arguments: [
            "TOKEN_ALPHABET = abcdefghijklmnopqrstuvwxyz",
            "PASSWORD_CHANGE_REQUIRED = someLongEnoughValue",
            "PASSWORD_CHANGE_REQUIRED_CODE = anotherLongValue",
        ]
    )
    func aNameThatMerelyDescribesASecretIsNotTreatedAsOne(_ text: String) {
        #expect(redactor.redact(text) == text)
    }

    @Test("the value that was masked never survives into the output")
    func theValueThatWasMaskedNeverSurvivesIntoTheOutput() {
        let redacted = redactor.redact("db url postgresql://appuser:hunter2secret@db/anchor")

        #expect(!redacted.contains("hunter2secret"))
        #expect(redacted.contains("postgresql://appuser:"))
        #expect(redacted.contains("@db/anchor"))
    }

    @Test("a private key block is masked whole, not line by line")
    func aPrivateKeyBlockIsMaskedWholeNotLineByLine() {
        let boundary = Self.credentialShapedSample("-----BEGIN OPENSSH PRIVATE", " KEY-----")
        let closing = Self.credentialShapedSample("-----END OPENSSH PRIVATE", " KEY-----")
        let block = """
            \(boundary)
            b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
            \(closing)
            """

        let redacted = redactor.redact("here it is\n\(block)\nthat was it")

        #expect(!redacted.contains("b3BlbnNzaC1rZXktdjEA"))
        #expect(redacted.contains("here it is"))
        #expect(redacted.contains("that was it"))
    }

    @Test("prose with no secret in it comes back untouched")
    func proseWithNoSecretInItComesBackUntouched() {
        let prose = "The engine drains the queue and the coordinator starts it at launch."

        #expect(redactor.redact(prose) == prose)
    }

    @Test("two secrets of different kinds in one line are both masked")
    func twoSecretsOfDifferentKindsInOneLineAreBothMasked() {
        let awsKey = Self.credentialShapedSample("AKIA", "IOSFODNN7EXAMPLE")
        let githubToken = Self.credentialShapedSample(
            "ghp", "_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

        let redacted = redactor.redact("\(awsKey) and \(githubToken)")

        #expect(redacted.contains(SessionSecretRedactor.marker(for: "aws-access-key")))
        #expect(redacted.contains(SessionSecretRedactor.marker(for: "github-token")))
    }
}
