public protocol SyncFailureClassifying: Sendable {
    func isWorthRetrying(_ failure: any Error) -> Bool
}
