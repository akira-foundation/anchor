import Foundation

public struct ContextReadGeneration: Sendable, Equatable {
    public let identifier: UUID

    public init(identifier: UUID) { self.identifier = identifier }
}

public protocol ContextAvailabilityReading: Sendable {
    func loadAvailableGeneration() async throws -> ContextReadGeneration
}
