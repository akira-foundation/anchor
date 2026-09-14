import SQLite3

public protocol SQLiteStatementObserving: Sendable {
    func recordCompletion(ofStatement statement: String)
}

enum SQLiteStatementTrace {
    static func install(
        _ observer: any SQLiteStatementObserving, on connection: OpaquePointer
    ) throws(SQLiteDatabase.Failure) {
        let context = Unmanaged.passRetained(Observation(observer: observer)).toOpaque()
        let status = sqlite3_trace_v2(
            connection, UInt32(SQLITE_TRACE_PROFILE | SQLITE_TRACE_CLOSE), recordTrace, context)
        guard status == SQLITE_OK else {
            Unmanaged<Observation>.fromOpaque(context).release()
            throw .statementRefused(String(cString: sqlite3_errmsg(connection)))
        }
    }

    private final class Observation {
        let observer: any SQLiteStatementObserving

        init(observer: any SQLiteStatementObserving) {
            self.observer = observer
        }
    }

    private static let recordTrace:
        @convention(c) (
            UInt32, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
        ) -> Int32 = { event, context, statement, _ in
            guard let context else { return 0 }
            let observation = Unmanaged<Observation>.fromOpaque(context)
            guard event != UInt32(SQLITE_TRACE_CLOSE) else {
                observation.release()
                return 0
            }
            guard let statement, let sql = sqlite3_sql(OpaquePointer(statement)) else { return 0 }
            observation.takeUnretainedValue().observer.recordCompletion(
                ofStatement: String(cString: sql))
            return 0
        }
}
