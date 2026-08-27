import AnchorDomain
import AnchorStorage
import CloudKit
import Foundation
import Testing

@testable import AnchorPlatformAppleCloud

@Suite("CloudKit record schema")
struct CloudKitRecordSchemaTests {
    private func draft(byteCount: Int) throws -> CloudRecordDraft {
        CloudRecordDraft(
            name: "object-test",
            key: try #require(StorageKey(rawValue: "projects/anchor/index")),
            contents: Data(repeating: 0x61, count: byteCount)
        )
    }

    private func emptyRecord() -> CKRecord {
        CKRecord(
            recordType: CloudKitRecordSchema.objectRecordType, recordID: .init(recordName: "r"))
    }

    @Test("contents that fit the record limit travel inside the record")
    func contentsThatFitTheRecordLimitTravelInsideTheRecord() throws {
        let record = emptyRecord()

        let stagedURL = try CloudKitRecordSchema.apply(
            try draft(byteCount: CloudKitRecordSchema.maximumInlineByteCount),
            to: record,
            stagingContentsAt: FileManager.default.temporaryDirectory
        )

        #expect(stagedURL == nil)
        #expect(record[CloudKitRecordSchema.inlineContentsField] as? Data != nil)
        #expect(record[CloudKitRecordSchema.attachedContentsField] as? CKAsset == nil)
    }

    @Test("contents past the record limit travel as an attachment")
    func contentsPastTheRecordLimitTravelAsAnAttachment() throws {
        let record = emptyRecord()

        let stagedURL = try CloudKitRecordSchema.apply(
            try draft(byteCount: CloudKitRecordSchema.maximumInlineByteCount + 1),
            to: record,
            stagingContentsAt: FileManager.default.temporaryDirectory
        )

        defer { stagedURL.map { try? FileManager.default.removeItem(at: $0) } }

        #expect(stagedURL != nil)
        #expect(record[CloudKitRecordSchema.inlineContentsField] as? Data == nil)
        #expect(record[CloudKitRecordSchema.attachedContentsField] as? CKAsset != nil)
    }

    @Test("the byte size is readable without the contents")
    func byteSizeIsReadableWithoutTheContents() throws {
        let record = emptyRecord()

        _ = try CloudKitRecordSchema.apply(
            try draft(byteCount: 12), to: record,
            stagingContentsAt: FileManager.default.temporaryDirectory)

        #expect(record[CloudKitRecordSchema.byteSizeField] as? Int == 12)
    }

    @Test("a record that carries neither key nor kind is not read as a log entry")
    func recordThatCarriesNeitherKeyNorKindIsNotReadAsALogEntry() {
        #expect(CloudKitRecordSchema.logEntry(from: emptyRecord()) == nil)
    }

    @Test("a log entry survives the round trip through a record")
    func logEntrySurvivesTheRoundTripThroughARecord() throws {
        let entry = CloudLogEntry(
            name: "r",
            key: try #require(StorageKey(rawValue: "devices/laptop")),
            kind: .deleted
        )
        let record = emptyRecord()

        CloudKitRecordSchema.apply(entry, to: record)

        #expect(CloudKitRecordSchema.logEntry(from: record) == entry)
    }
}
