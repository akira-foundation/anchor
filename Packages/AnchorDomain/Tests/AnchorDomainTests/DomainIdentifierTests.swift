import Foundation
import Testing

@testable import AnchorDomain

@Suite("Domain identifiers")
struct DomainIdentifierTests {
    @Test("a project identifier preserves the raw value it was restored from")
    func projectIdentifierPreservesTheRawValueItWasRestoredFrom() throws {
        let expectedRawValue = UUID().uuidString

        let projectIdentifier = try #require(ProjectIdentifier(rawValue: expectedRawValue))

        #expect(projectIdentifier.rawValue == expectedRawValue)
    }

    @Test("an artifact identifier preserves the raw value it was restored from")
    func artifactIdentifierPreservesTheRawValueItWasRestoredFrom() throws {
        let expectedRawValue = UUID().uuidString

        let artifactIdentifier = try #require(ArtifactIdentifier(rawValue: expectedRawValue))

        #expect(artifactIdentifier.rawValue == expectedRawValue)
    }
}
