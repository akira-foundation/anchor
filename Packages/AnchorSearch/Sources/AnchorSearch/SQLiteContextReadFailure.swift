public enum SQLiteContextReadFailure: Error, Sendable, Equatable {
    case malformedSession
    case malformedEntry
}
