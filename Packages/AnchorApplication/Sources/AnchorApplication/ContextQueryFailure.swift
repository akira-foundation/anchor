public enum ContextQueryFailure: Error, Sendable, Equatable {
    case workspaceNotConfigured
    case workspaceNotAuthorized
    case contextUnavailable
    case entityNotFound
    case invalidCursor
    case contentIsNotText
    case readFailed
}

public enum ContextCursorFailure: Error, Sendable, Equatable {
    case invalid
}

func queryContext<Output: Sendable>(
    availability: any ContextAvailabilityReading,
    _ operation: () async throws -> Output
) async throws(ContextQueryFailure) -> Output {
    do {
        let generation = try await availability.loadAvailableGeneration()
        let output = try await operation()
        guard try await availability.loadAvailableGeneration() == generation else {
            throw ContextQueryFailure.contextUnavailable
        }
        return output
    } catch let failure as ContextQueryFailure {
        throw failure
    } catch is ContextCursorFailure {
        throw .invalidCursor
    } catch {
        throw .readFailed
    }
}
