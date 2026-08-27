import AnchorDomain
import AnchorPlatformAppleCloud
import Foundation
import Testing

@Suite("Cloud record naming")
struct CloudRecordNamingTests {
    private func key(_ rawValue: String) throws -> StorageKey {
        try #require(StorageKey(rawValue: rawValue))
    }

    @Test("the same key always names the same record")
    func sameKeyAlwaysNamesTheSameRecord() throws {
        let storageKey = try key("projects/anchor/index")

        #expect(
            CloudRecordNaming.objectRecordName(for: storageKey)
                == CloudRecordNaming.objectRecordName(for: storageKey))
    }

    @Test("different keys name different records")
    func differentKeysNameDifferentRecords() throws {
        let anchor = CloudRecordNaming.objectRecordName(for: try key("projects/anchor"))
        let anchorage = CloudRecordNaming.objectRecordName(for: try key("projects/anchorage"))

        #expect(anchor != anchorage)
    }

    @Test("a name CloudKit would refuse is never produced")
    func nameCloudKitWouldRefuseIsNeverProduced() throws {
        let longKey = try key(String(repeating: "é", count: 400))
        let name = CloudRecordNaming.objectRecordName(for: longKey)

        let isEntirelyASCII = name.allSatisfy(\.isASCII)

        #expect(isEntirelyASCII)
        #expect(name.count <= 255)
        #expect(!name.hasPrefix("_"))
    }

    @Test("log names sort in the order the entries were recorded")
    func logNamesSortInTheOrderTheEntriesWereRecorded() {
        let earlier = CloudRecordNaming.logRecordName(
            recordedAt: Date(timeIntervalSince1970: 1), disambiguator: "zzzz")
        let later = CloudRecordNaming.logRecordName(
            recordedAt: Date(timeIntervalSince1970: 2), disambiguator: "aaaa")

        #expect(earlier < later)
    }
}
