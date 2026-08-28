import AnchorDomain
import Foundation

public protocol ArtifactContentStore: Sendable {
    func storeContent(_ content: Data, forRevision revisionID: RevisionID) async throws
    func content(forRevision revisionID: RevisionID) async throws -> Data?
    func dropContent(forRevision revisionID: RevisionID) async throws
}
