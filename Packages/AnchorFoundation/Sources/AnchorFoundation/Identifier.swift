import Foundation

public struct Identifier<Subject>: ValidatedRawValue, Hashable, CustomStringConvertible {
    public static var rawValueRequirement: String { "Identifier raw value is not a UUID" }

    public let rawValue: String

    public init() {
        rawValue = UUID().uuidString
    }

    public init?(rawValue: String) {
        guard let parsedUniversallyUniqueIdentifier = UUID(uuidString: rawValue) else { return nil }

        self.rawValue = parsedUniversallyUniqueIdentifier.uuidString
    }

    public var description: String { rawValue }

    public static func == (lhs: Identifier<Subject>, rhs: Identifier<Subject>) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}
