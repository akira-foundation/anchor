import Foundation
import SQLite3

public actor SQLiteDatabase {
    public enum Failure: Error, Sendable, Equatable {
        case couldNotOpen(String)
        case statementRefused(String)
    }

    private let handle: SQLiteHandle
    private let readOnly: Bool

    public init(
        fileURL: URL?, readOnly: Bool = false,
        statementObserver: (any SQLiteStatementObserving)? = nil
    ) throws(Failure) {
        var opened: OpaquePointer?
        let location = fileURL?.path(percentEncoded: false) ?? ":memory:"

        self.readOnly = readOnly
        if !readOnly {
            fileURL.map {
                try? FileManager.default.createDirectory(
                    at: $0.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
        }

        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(location, &opened, flags, nil) == SQLITE_OK, let opened else {
            if let opened { sqlite3_close(opened) }
            throw .couldNotOpen(location)
        }

        handle = SQLiteHandle(opened)
        try Self.configureFileDatabase(opened, fileURL: fileURL, readOnly: readOnly)
        if let statementObserver {
            try SQLiteStatementTrace.install(statementObserver, on: opened)
        }
    }

    public func execute(_ statements: String) throws(Failure) {
        guard sqlite3_exec(handle.pointer, statements, nil, nil, nil) == SQLITE_OK else {
            throw .statementRefused(lastMessage())
        }
    }

    public func withinTransaction<Output: Sendable>(
        _ operation: @Sendable (isolated SQLiteDatabase) throws -> Output
    ) throws -> Output {
        do {
            try execute(readOnly ? "BEGIN;" : "BEGIN IMMEDIATE;")
            let output = try operation(self)
            try execute("COMMIT;")
            return output
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    @discardableResult
    public func run(
        _ statement: String, _ parameters: [SQLiteValue] = []
    ) throws(Failure) -> [[String: SQLiteValue]] {
        let prepared = try prepare(statement, parameters)

        defer { sqlite3_finalize(prepared) }

        var rows: [[String: SQLiteValue]] = []

        while true {
            let stepped = sqlite3_step(prepared)

            guard stepped != SQLITE_DONE else { return rows }
            guard stepped == SQLITE_ROW else { throw .statementRefused(lastMessage()) }

            rows.append(Self.row(of: prepared))
        }
    }

    private func prepare(
        _ statement: String, _ parameters: [SQLiteValue]
    ) throws(Failure) -> OpaquePointer {
        var prepared: OpaquePointer?

        guard sqlite3_prepare_v2(handle.pointer, statement, -1, &prepared, nil) == SQLITE_OK,
            let prepared
        else { throw .statementRefused(lastMessage()) }

        for (offset, parameter) in parameters.enumerated() {
            Self.bind(parameter, at: Int32(offset + 1), to: prepared)
        }

        return prepared
    }

    private static func configureFileDatabase(
        _ handle: OpaquePointer, fileURL: URL?, readOnly: Bool
    ) throws(Failure) {
        guard fileURL != nil else { return }
        guard sqlite3_busy_timeout(handle, 5_000) == SQLITE_OK else {
            throw .statementRefused(String(cString: sqlite3_errmsg(handle)))
        }
        guard
            sqlite3_exec(
                handle,
                readOnly
                    ? "PRAGMA foreign_keys=ON;"
                    : "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;", nil, nil, nil
            ) == SQLITE_OK
        else {
            throw .statementRefused(String(cString: sqlite3_errmsg(handle)))
        }
    }

    private static func bind(_ value: SQLiteValue, at index: Int32, to statement: OpaquePointer) {
        switch value {
        case .text(let text):
            sqlite3_bind_text(
                statement, index, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        case .integer(let number):
            sqlite3_bind_int64(statement, index, number)
        case .null:
            sqlite3_bind_null(statement, index)
        }
    }

    private static func row(of statement: OpaquePointer) -> [String: SQLiteValue] {
        var row: [String: SQLiteValue] = [:]

        for column in 0..<sqlite3_column_count(statement) {
            let name = String(cString: sqlite3_column_name(statement, column))
            row[name] = value(of: statement, at: column)
        }

        return row
    }

    private static func value(of statement: OpaquePointer, at column: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER: .integer(sqlite3_column_int64(statement, column))
        case SQLITE_NULL: .null
        default: .text(String(cString: sqlite3_column_text(statement, column)))
        }
    }

    private func lastMessage() -> String {
        String(cString: sqlite3_errmsg(handle.pointer))
    }
}

final class SQLiteHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit { sqlite3_close(pointer) }
}
