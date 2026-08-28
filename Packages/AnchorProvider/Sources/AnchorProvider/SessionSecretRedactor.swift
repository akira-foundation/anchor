import Foundation

public struct SessionSecretRule: Sendable {
    public let name: String
    public let pattern: String
    public let maskedGroup: Int

    public init(name: String, pattern: String, maskedGroup: Int = 0) {
        self.name = name
        self.pattern = pattern
        self.maskedGroup = maskedGroup
    }
}

public struct SessionSecretRedactor: Sendable {
    public static let rules: [SessionSecretRule] = [
        SessionSecretRule(
            name: "url-credentials",
            pattern: "[a-z][a-z0-9+.\\-]*://[^/\\s:@\"]{2,}:([^/\\s@\"]{6,})@",
            maskedGroup: 1
        ),
        SessionSecretRule(
            name: "assigned-secret",
            pattern:
                "\\b[A-Z0-9_]*(?:TOKEN|PASSWORD|PASSWD|SECRET|API_KEY|APIKEY|ACCESS_KEY"
                + "|PRIVATE_KEY)\\s*[:=]\\s*[\"']?([A-Za-z0-9/+_\\-.]{16,})",
            maskedGroup: 1
        ),
        SessionSecretRule(
            name: "json-web-token",
            pattern: "\\beyJ[A-Za-z0-9_\\-]{10,}\\.[A-Za-z0-9_\\-]{10,}\\.[A-Za-z0-9_\\-]{10,}"
        ),
        SessionSecretRule(name: "google-key", pattern: "AIza[0-9A-Za-z_\\-]{35}"),
        SessionSecretRule(name: "stripe-key", pattern: "[sr]k_(?:live|test)_[A-Za-z0-9]{20,}"),
        SessionSecretRule(name: "anthropic-key", pattern: "sk-ant-[A-Za-z0-9_\\-]{20,}"),
        SessionSecretRule(name: "openai-key", pattern: "sk-proj-[A-Za-z0-9_\\-]{20,}"),
        SessionSecretRule(name: "github-token", pattern: "gh[pousr]_[A-Za-z0-9]{36,}"),
        SessionSecretRule(name: "slack-token", pattern: "xox[baprs]-[A-Za-z0-9\\-]{10,}"),
        SessionSecretRule(name: "aws-access-key", pattern: "AKIA[0-9A-Z]{16}"),
        SessionSecretRule(
            name: "private-key-block",
            pattern: "-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----"
        ),
    ]

    private let compiled: [(rule: SessionSecretRule, expression: NSRegularExpression)]

    public init(rules: [SessionSecretRule] = SessionSecretRedactor.rules) {
        compiled = rules.compactMap { rule in
            guard let expression = try? NSRegularExpression(pattern: rule.pattern) else {
                return nil
            }

            return (rule, expression)
        }
    }

    public func redact(_ text: String) -> String {
        compiled.reduce(text) { redacted, entry in
            mask(redacted, with: entry.rule, using: entry.expression)
        }
    }

    private func mask(
        _ text: String, with rule: SessionSecretRule, using expression: NSRegularExpression
    ) -> String {
        let matches = expression.matches(
            in: text, range: NSRange(text.startIndex..., in: text)
        )
        var masked = text

        for match in matches.reversed() {
            let group = min(rule.maskedGroup, match.numberOfRanges - 1)

            guard let range = Range(match.range(at: group), in: masked) else { continue }

            masked.replaceSubrange(range, with: Self.marker(for: rule.name))
        }

        return masked
    }

    public static func marker(for ruleName: String) -> String {
        "[redacted:\(ruleName)]"
    }
}
