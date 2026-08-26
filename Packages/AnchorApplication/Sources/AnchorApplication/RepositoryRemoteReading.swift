import AnchorDomain
import Foundation

public protocol RepositoryRemoteReading: Sendable {
    func readRepositoryRemote(atDirectory directoryURL: URL) async throws -> RepositoryRemoteOutcome
}

public enum RepositoryRemoteOutcome: Sendable, Equatable {
    case remote(CanonicalRepositoryRemote)
    case repositoryWithoutRemote
    case notARepository
    case severalRemotes([String])
}

public enum RepositoryRemoteFailure: Error, Sendable, Equatable {
    case gitUnavailable
    case directoryUnreadable(URL)
}
