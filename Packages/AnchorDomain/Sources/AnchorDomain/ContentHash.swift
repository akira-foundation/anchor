import AnchorFoundation

public struct ContentHash: ValidatedRawValue, Hashable, CustomStringConvertible {
    public static let expectedDigestLength = 64

    public static var rawValueRequirement: String {
        "Content hash is not a lowercase hexadecimal SHA-256 digest"
    }

    private static let lowercaseHexadecimalBytes = Set("0123456789abcdef".utf8)

    public let rawValue: String

    public init?(rawValue: String) {
        let rawValueBytes = Array(rawValue.utf8)

        guard rawValueBytes.count == Self.expectedDigestLength else { return nil }
        guard rawValueBytes.allSatisfy(Self.lowercaseHexadecimalBytes.contains) else { return nil }

        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}
