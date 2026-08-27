import AnchorDomain
import AnchorStorage
import CloudKit
import Foundation

enum CloudKitRecordSchema {
    static let objectRecordType = "AnchorObject"
    static let logRecordType = "AnchorChangeLog"

    static let keyField = "storageKey"
    static let byteSizeField = "byteSize"
    static let inlineContentsField = "inlineContents"
    static let attachedContentsField = "attachedContents"
    static let changeKindField = "changeKind"

    private static let cloudKitRecordDataLimitInBytes = 1_000_000
    private static let reserveForOtherRecordFieldsInBytes = 300_000

    static let maximumInlineByteCount =
        cloudKitRecordDataLimitInBytes - reserveForOtherRecordFieldsInBytes

    static func carriesContentsInline(byteCount: Int) -> Bool {
        byteCount <= maximumInlineByteCount
    }

    static func snapshot(from record: CKRecord) -> CloudRecordSnapshot? {
        guard let rawKey = record[keyField] as? String,
            let key = StorageKey(rawValue: rawKey),
            let byteSize = record[byteSizeField] as? Int,
            let versionTag = record.recordChangeTag,
            let modifiedAt = record.modificationDate
        else { return nil }

        return CloudRecordSnapshot(
            name: record.recordID.recordName,
            key: key,
            byteSize: byteSize,
            contents: contents(of: record),
            versionTag: StorageVersionTag(rawValue: versionTag),
            modifiedAt: modifiedAt
        )
    }

    static func logEntry(from record: CKRecord) -> CloudLogEntry? {
        guard let rawKey = record[keyField] as? String,
            let key = StorageKey(rawValue: rawKey),
            let rawKind = record[changeKindField] as? String,
            let kind = StorageChangeKind(rawValue: rawKind)
        else { return nil }

        return CloudLogEntry(name: record.recordID.recordName, key: key, kind: kind)
    }

    static func apply(_ entry: CloudLogEntry, to record: CKRecord) {
        record[keyField] = entry.key.rawValue
        record[changeKindField] = entry.kind.rawValue
    }

    static func apply(
        _ draft: CloudRecordDraft, to record: CKRecord, stagingContentsAt directory: URL
    ) throws -> URL? {
        record[keyField] = draft.key.rawValue
        record[byteSizeField] = draft.contents.count

        guard !carriesContentsInline(byteCount: draft.contents.count) else {
            record[inlineContentsField] = draft.contents
            record[attachedContentsField] = nil

            return nil
        }

        let stagedURL = directory.appending(path: UUID().uuidString)
        try draft.contents.write(to: stagedURL)
        record[inlineContentsField] = nil
        record[attachedContentsField] = CKAsset(fileURL: stagedURL)

        return stagedURL
    }

    private static func contents(of record: CKRecord) -> Data? {
        if let inline = record[inlineContentsField] as? Data { return inline }

        guard let asset = record[attachedContentsField] as? CKAsset,
            let fileURL = asset.fileURL
        else { return nil }

        return try? Data(contentsOf: fileURL)
    }
}
