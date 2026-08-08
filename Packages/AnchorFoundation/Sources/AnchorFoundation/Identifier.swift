import Foundation

public struct Identifier<Subject>: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String

    public init() {
        rawValue = UUID().uuidString
    }

    public init?(rawValue: String) {
        guard UUID(uuidString: rawValue) != nil else { return nil }

        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func == (lhs: Identifier<Subject>, rhs: Identifier<Subject>) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}
