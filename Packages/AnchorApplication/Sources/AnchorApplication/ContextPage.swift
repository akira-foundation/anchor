import Foundation

public struct ContextPageRequest: Sendable, Hashable {
    public let limit: Int
    public let cursor: ContextPageCursor?

    public init?(
        limit: Int?,
        cursor: ContextPageCursor? = nil,
        defaultLimit: Int = 20,
        maximumLimit: Int
    ) {
        guard maximumLimit > 0, (1...maximumLimit).contains(defaultLimit) else { return nil }

        let resolvedLimit = limit ?? defaultLimit
        guard (1...maximumLimit).contains(resolvedLimit) else { return nil }

        self.limit = resolvedLimit
        self.cursor = cursor
    }
}

public struct ContextPageCursor: Sendable, Hashable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty,
            rawValue == rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }

        self.rawValue = rawValue
    }
}

public struct ContextPage<Element: Sendable & Hashable>: Sendable, Hashable {
    public let records: [Element]
    public let nextCursor: ContextPageCursor?

    public init(records: [Element], nextCursor: ContextPageCursor?) {
        self.records = records
        self.nextCursor = nextCursor
    }
}
