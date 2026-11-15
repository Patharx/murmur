#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif
import Foundation

struct SQLiteError: Error, Equatable {
    var message: String
}

final class SQLiteConnection {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(path, &db, flags, nil)
        guard code == SQLITE_OK, let db else {
            throw SQLiteError(message: "open failed (\(code))")
        }
        handle = db
        try execute("PRAGMA journal_mode=DELETE;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func execute(_ sql: String) throws {
        try check(sqlite3_exec(handle, sql, nil, nil, nil), sql)
    }

    func run(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE || code == SQLITE_ROW else {
            throw error("step \(sql)")
        }
    }

    func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [[String: SQLiteValue]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: SQLiteValue] = [:]
            let count = sqlite3_column_count(statement)
            for index in 0..<count {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = column(statement, index: index)
            }
            rows.append(row)
        }
        return rows
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        try check(code, sql)
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .null:
                code = sqlite3_bind_null(statement, index)
            case .int(let int):
                code = sqlite3_bind_int64(statement, index, int)
            case .text(let text):
                code = sqlite3_bind_text(statement, index, text, -1, transient)
            }
            try check(code, "bind")
        }
    }

    private func column(_ statement: OpaquePointer?, index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL:
            return .null
        case SQLITE_INTEGER:
            return .int(sqlite3_column_int64(statement, index))
        case SQLITE_TEXT:
            guard let pointer = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: pointer))
        default:
            guard let pointer = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: pointer))
        }
    }

    private func check(_ code: Int32, _ sql: String) throws {
        if code != SQLITE_OK && code != SQLITE_DONE && code != SQLITE_ROW {
            throw error(sql)
        }
    }

    private func error(_ context: String) -> SQLiteError {
        let message = handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown"
        return SQLiteError(message: "\(context): \(message)")
    }
}

enum SQLiteValue: Equatable {
    case null
    case int(Int64)
    case text(String)

    var int: Int64? {
        if case .int(let value) = self { return value }
        return nil
    }

    var textValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}
