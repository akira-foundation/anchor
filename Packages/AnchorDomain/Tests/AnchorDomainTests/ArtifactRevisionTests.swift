import Foundation
import Testing

@testable import AnchorDomain

@Suite("ArtifactRevision")
struct ArtifactRevisionTests {
    private static let digest = String(repeating: "a1b2c3d4", count: 8)

    @Test("a revision without a parent is a valid ancestry root")
    func revisionWithoutAParentIsAValidAncestryRoot() throws {
        let contentHash = try #require(ContentHash(rawValue: Self.digest))

        let rootRevision = try #require(
            ArtifactRevision(
                id: RevisionID(),
                artifactID: ArtifactID(),
                parentRevisionID: nil,
                contentHash: contentHash,
                deviceID: DeviceID(),
                createdAt: Date(timeIntervalSince1970: 0)
            )
        )

        #expect(rootRevision.parentRevisionID == nil)
    }

    @Test("a revision cannot be its own parent")
    func revisionCannotBeItsOwnParent() throws {
        let contentHash = try #require(ContentHash(rawValue: Self.digest))
        let revisionID = RevisionID()

        let selfParentedRevision = ArtifactRevision(
            id: revisionID,
            artifactID: ArtifactID(),
            parentRevisionID: revisionID,
            contentHash: contentHash,
            deviceID: DeviceID(),
            createdAt: Date(timeIntervalSince1970: 0)
        )

        #expect(selfParentedRevision == nil)
    }

    @Test("a revision descending from another revision keeps its parent")
    func revisionDescendingFromAnotherRevisionKeepsItsParent() throws {
        let contentHash = try #require(ContentHash(rawValue: Self.digest))
        let parentRevisionID = RevisionID()

        let childRevision = try #require(
            ArtifactRevision(
                id: RevisionID(),
                artifactID: ArtifactID(),
                parentRevisionID: parentRevisionID,
                contentHash: contentHash,
                deviceID: DeviceID(),
                createdAt: Date(timeIntervalSince1970: 0)
            )
        )

        #expect(childRevision.parentRevisionID == parentRevisionID)
    }
}

@Suite("ArtifactRevision decoding")
struct ArtifactRevisionDecodingTests {
    private static let digest = String(repeating: "a1b2c3d4", count: 8)

    private func encodedRevision(id: String, parentRevisionID: String?) -> Data {
        let parentField = parentRevisionID.map { "\"parentRevisionID\":\"\($0)\"," } ?? ""

        return Data(
            """
            {"id":"\(id)",\(parentField)"artifactID":"\(UUID().uuidString)",\
            "contentHash":"\(Self.digest)","deviceID":"\(UUID().uuidString)","createdAt":0}
            """.utf8
        )
    }

    @Test("decoding a revision that is its own parent is rejected")
    func decodingARevisionThatIsItsOwnParentIsRejected() {
        let revisionRawValue = UUID().uuidString

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ArtifactRevision.self,
                from: encodedRevision(id: revisionRawValue, parentRevisionID: revisionRawValue)
            )
        }
    }

    @Test("decoding a revision that is its own parent in a different letter case is rejected")
    func decodingARevisionThatIsItsOwnParentInADifferentLetterCaseIsRejected() {
        let revisionRawValue = UUID().uuidString

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ArtifactRevision.self,
                from: encodedRevision(id: revisionRawValue, parentRevisionID: revisionRawValue.lowercased())
            )
        }
    }

    @Test("decoding an ancestry root without a parent succeeds")
    func decodingAnAncestryRootWithoutAParentSucceeds() throws {
        let decodedRevision = try JSONDecoder().decode(
            ArtifactRevision.self,
            from: encodedRevision(id: UUID().uuidString, parentRevisionID: nil)
        )

        #expect(decodedRevision.parentRevisionID == nil)
    }
}
