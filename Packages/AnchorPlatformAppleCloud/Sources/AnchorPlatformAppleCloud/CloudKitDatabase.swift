import AnchorDomain
import AnchorStorage
import CloudKit
import Foundation

public actor CloudKitDatabase: CloudRecordDatabase {
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let stagingDirectory: URL
    private var zoneIsKnownToExist = false

    public init(
        container: CKContainer,
        zoneName: String = "AnchorContext",
        stagingDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.database = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        self.stagingDirectory = stagingDirectory
    }

    public func snapshot(
        named name: String
    ) async throws(CloudDatabaseFailure)
        -> CloudRecordSnapshot?
    {
        guard let record = try await fetchRecord(named: name) else { return nil }

        return CloudKitRecordSchema.snapshot(from: record)
    }

    public func objectSnapshots() async throws(CloudDatabaseFailure) -> [CloudRecordSnapshot] {
        try await enumerateZone()
            .filter { $0.recordType == CloudKitRecordSchema.objectRecordType }
            .compactMap(CloudKitRecordSchema.snapshot(from:))
    }

    @discardableResult
    public func save(
        _ draft: CloudRecordDraft,
        precondition: StorageWritePrecondition,
        recording entry: CloudLogEntry
    ) async throws(CloudDatabaseFailure) -> CloudRecordSnapshot {
        try await ensureZoneExists()

        let record = try await recordToSave(for: draft, precondition: precondition)
        var stagedURL: URL?

        do {
            stagedURL = try CloudKitRecordSchema.apply(
                draft, to: record, stagingContentsAt: stagingDirectory)
        } catch {
            throw .transportUnavailable
        }

        defer { stagedURL.map { try? FileManager.default.removeItem(at: $0) } }

        let saved = try await commit(
            saving: [record, logRecord(for: entry)],
            deleting: [],
            savePolicy: savePolicy(for: precondition)
        )

        guard
            let snapshot = saved.first(where: { $0.recordID == record.recordID })
                .flatMap(CloudKitRecordSchema.snapshot(from:))
        else { throw .transportUnavailable }

        return snapshot
    }

    public func remove(
        recordNamed name: String, recording entry: CloudLogEntry
    ) async throws(CloudDatabaseFailure) {
        try await ensureZoneExists()

        _ = try await commit(
            saving: [logRecord(for: entry)],
            deleting: [CKRecord.ID(recordName: name, zoneID: zoneID)],
            savePolicy: .allKeys
        )
    }

    public func logEntries(after token: Data?) async throws(CloudDatabaseFailure) -> CloudLogPage {
        try await ensureZoneExists()

        let page = try await changedRecords(since: try decodeToken(token))
        let entries =
            page.records
            .filter { $0.recordType == CloudKitRecordSchema.logRecordType }
            .compactMap(CloudKitRecordSchema.logEntry(from:))
            .sorted { $0.name < $1.name }

        return CloudLogPage(
            entries: entries,
            token: encodeToken(page.token),
            hasMore: page.hasMore
        )
    }

    private func recordToSave(
        for draft: CloudRecordDraft, precondition: StorageWritePrecondition
    ) async throws(CloudDatabaseFailure) -> CKRecord {
        let recordID = CKRecord.ID(recordName: draft.name, zoneID: zoneID)

        switch precondition {
        case .none, .objectIsAbsent:
            return CKRecord(recordType: CloudKitRecordSchema.objectRecordType, recordID: recordID)
        case .versionTagMatches(let expected):
            guard let existing = try await fetchRecord(named: draft.name) else {
                throw .versionTagMismatch(currentVersionTag: nil)
            }
            guard existing.recordChangeTag == expected.rawValue else {
                throw .versionTagMismatch(
                    currentVersionTag: existing.recordChangeTag.map(StorageVersionTag.init))
            }

            return existing
        }
    }

    private func savePolicy(
        for precondition: StorageWritePrecondition
    ) -> CKModifyRecordsOperation.RecordSavePolicy {
        guard case .none = precondition else { return .ifServerRecordUnchanged }

        return .allKeys
    }

    private func logRecord(for entry: CloudLogEntry) -> CKRecord {
        let record = CKRecord(
            recordType: CloudKitRecordSchema.logRecordType,
            recordID: CKRecord.ID(recordName: entry.name, zoneID: zoneID)
        )
        CloudKitRecordSchema.apply(entry, to: record)

        return record
    }

    private func fetchRecord(named name: String) async throws(CloudDatabaseFailure) -> CKRecord? {
        do {
            return try await database.record(for: CKRecord.ID(recordName: name, zoneID: zoneID))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch let error as CKError where error.code == .zoneNotFound {
            return nil
        } catch {
            throw CloudKitFailureMapping.failure(from: error)
        }
    }

    private func commit(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy
    ) async throws(CloudDatabaseFailure) -> [CKRecord] {
        do {
            let results = try await database.modifyRecords(
                saving: records,
                deleting: recordIDs,
                savePolicy: savePolicy,
                atomically: true
            )

            return try results.saveResults.values.map { try $0.get() }
        } catch {
            throw CloudKitFailureMapping.failure(from: error)
        }
    }

    private func enumerateZone() async throws(CloudDatabaseFailure) -> [CKRecord] {
        try await ensureZoneExists()

        var token: CKServerChangeToken?
        var records: [CKRecord] = []

        while true {
            let page = try await changedRecords(since: token)
            records += page.records
            token = page.token

            guard page.hasMore else { return records }
        }
    }

    private func changedRecords(
        since token: CKServerChangeToken?
    ) async throws(CloudDatabaseFailure) -> (
        records: [CKRecord], token: CKServerChangeToken, hasMore: Bool
    ) {
        do {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)

            return (
                changes.modificationResultsByID.values.compactMap { try? $0.get().record },
                changes.changeToken,
                changes.moreComing
            )
        } catch {
            throw CloudKitFailureMapping.failure(from: error)
        }
    }

    private func ensureZoneExists() async throws(CloudDatabaseFailure) {
        guard !zoneIsKnownToExist else { return }

        do {
            _ = try await database.modifyRecordZones(
                saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            zoneIsKnownToExist = true
        } catch {
            throw CloudKitFailureMapping.failure(from: error)
        }
    }

    private func decodeToken(_ token: Data?) throws(CloudDatabaseFailure) -> CKServerChangeToken? {
        guard let token else { return nil }

        guard
            let decoded = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self, from: token)
        else { throw .changeTokenExpired }

        return decoded
    }

    private func encodeToken(_ token: CKServerChangeToken) -> Data {
        (try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true))
            ?? Data()
    }
}
