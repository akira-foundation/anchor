import AnchorDomain
import AnchorPlatformAppleCloud
import AnchorStorage
import Foundation

actor InMemoryCloudRecordDatabase: CloudRecordDatabase {
    private var records: [String: CloudRecordSnapshot] = [:]
    private var log: [CloudLogEntry] = []
    private var issuedTagCount = 0
    private let modifiedAt: Date

    init(modifiedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.modifiedAt = modifiedAt
    }

    func snapshot(named name: String) async throws(CloudDatabaseFailure) -> CloudRecordSnapshot? {
        records[name]
    }

    func objectSnapshots() async throws(CloudDatabaseFailure) -> [CloudRecordSnapshot] {
        Array(records.values)
    }

    @discardableResult
    func save(
        _ draft: CloudRecordDraft,
        precondition: StorageWritePrecondition,
        recording entry: CloudLogEntry
    ) async throws(CloudDatabaseFailure) -> CloudRecordSnapshot {
        try verify(precondition, against: records[draft.name]?.versionTag)

        issuedTagCount += 1
        let snapshot = CloudRecordSnapshot(
            key: draft.key,
            byteSize: draft.contents.count,
            contents: draft.contents,
            versionTag: StorageVersionTag(rawValue: "tag-\(issuedTagCount)"),
            modifiedAt: modifiedAt
        )
        records[draft.name] = snapshot
        log.append(entry)

        return snapshot
    }

    func remove(
        recordNamed name: String, recording entry: CloudLogEntry
    ) async throws(CloudDatabaseFailure) {
        records.removeValue(forKey: name)
        log.append(entry)
    }

    func logEntries(after token: Data?) async throws(CloudDatabaseFailure) -> CloudLogPage {
        let consumed = token.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        let entries = Array(log.dropFirst(consumed))

        return CloudLogPage(
            entries: entries,
            token: Data(String(log.count).utf8),
            hasMore: false
        )
    }

    private func verify(
        _ precondition: StorageWritePrecondition, against currentVersionTag: StorageVersionTag?
    ) throws(CloudDatabaseFailure) {
        switch precondition {
        case .none:
            return
        case .objectIsAbsent:
            guard currentVersionTag != nil else { return }

            throw .versionTagMismatch(currentVersionTag: currentVersionTag)
        case .versionTagMatches(let expected):
            guard expected != currentVersionTag else { return }

            throw .versionTagMismatch(currentVersionTag: currentVersionTag)
        }
    }
}
