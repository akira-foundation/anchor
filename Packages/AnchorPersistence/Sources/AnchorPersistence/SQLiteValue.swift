import Foundation

public enum SQLiteValue: Sendable, Hashable {
    case text(String)
    case integer(Int64)
    case null

    public var text: String? {
        guard case .text(let value) = self else { return nil }

        return value
    }

    public var integer: Int64? {
        guard case .integer(let value) = self else { return nil }

        return value
    }
}
