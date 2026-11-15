import Foundation

public struct NoteRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var path: String
    public var title: String
    public var folder: String
    public var kind: String
    public var created: Date
    public var duration: Int?
    public var hasSummary: Bool
    public var body: String
    public var localMtime: Int64
    public var syncedMtime: Int64?
    public var driveId: String?
    public var driveRev: String?
    public var phoneOnly: Bool

    public var onPhoneOnly: Bool {
        guard let syncedMtime else { return true }
        return syncedMtime < localMtime
    }

    public init(
        id: String,
        path: String,
        title: String,
        folder: String,
        kind: String,
        created: Date,
        duration: Int?,
        hasSummary: Bool,
        body: String,
        localMtime: Int64,
        syncedMtime: Int64?,
        driveId: String? = nil,
        driveRev: String? = nil,
        phoneOnly: Bool = false
    ) {
        self.id = id
        self.path = path
        self.title = title
        self.folder = folder
        self.kind = kind
        self.created = created
        self.duration = duration
        self.hasSummary = hasSummary
        self.body = body
        self.localMtime = localMtime
        self.syncedMtime = syncedMtime
        self.driveId = driveId
        self.driveRev = driveRev
        self.phoneOnly = phoneOnly
    }
}

/// SQLite cache of the notebook. The files are the real copy; this table can be thrown away and rebuilt.
public final class NoteIndex {
    /// The table from ARCHITECTURE §4. Kept as text so the cache cannot quietly grow new columns.
    public static let createTableSQL = """
    CREATE TABLE IF NOT EXISTS notes (
      id           TEXT PRIMARY KEY,
      path         TEXT NOT NULL,
      drive_id     TEXT,
      drive_rev    TEXT,
      local_mtime  INTEGER NOT NULL,
      synced_mtime INTEGER,
      title        TEXT,
      folder       TEXT,
      kind         TEXT,
      created      INTEGER,
      duration     INTEGER,
      has_summary  INTEGER DEFAULT 0,
      body         TEXT,
      phone_only   INTEGER NOT NULL DEFAULT 0
    );
    """

    public static let createFTSSQL = """
    CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
      title, body, content='notes', content_rowid='rowid'
    );
    """

    private let db: SQLiteConnection
    private let lock = NSLock()

    public init(databaseURL: URL) throws {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        db = try SQLiteConnection(path: databaseURL.path)
        try db.execute(Self.createTableSQL)
        try db.execute(Self.createFTSSQL)
        // Databases created before phone_only existed still open. A duplicate column is ignored.
        try? db.execute("ALTER TABLE notes ADD COLUMN phone_only INTEGER NOT NULL DEFAULT 0")
        try db.execute("""
        CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
          INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
        END;
        """)
        try db.execute("""
        CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
          INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
        END;
        """)
        try db.execute("""
        CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
          INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
          INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
        END;
        """)
    }

    public func upsert(_ row: NoteRow) throws {
        try lock.withLock {
            try db.run("""
            INSERT INTO notes (
              id, path, drive_id, drive_rev, local_mtime, synced_mtime,
              title, folder, kind, created, duration, has_summary, body, phone_only
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              path = excluded.path,
              drive_id = excluded.drive_id,
              drive_rev = excluded.drive_rev,
              local_mtime = excluded.local_mtime,
              synced_mtime = excluded.synced_mtime,
              title = excluded.title,
              folder = excluded.folder,
              kind = excluded.kind,
              created = excluded.created,
              duration = excluded.duration,
              has_summary = excluded.has_summary,
              body = excluded.body,
              phone_only = excluded.phone_only
            """, bindings: [
                .text(row.id),
                .text(row.path),
                row.driveId.map(SQLiteValue.text) ?? .null,
                row.driveRev.map(SQLiteValue.text) ?? .null,
                .int(row.localMtime),
                row.syncedMtime.map(SQLiteValue.int) ?? .null,
                .text(row.title),
                .text(row.folder),
                .text(row.kind),
                .int(Int64(row.created.timeIntervalSince1970 * 1000)),
                row.duration.map { .int(Int64($0)) } ?? .null,
                .int(row.hasSummary ? 1 : 0),
                .text(row.body),
                .int(row.phoneOnly ? 1 : 0),
            ])
        }
    }

    public func row(id: String) throws -> NoteRow? {
        try lock.withLock {
            let rows = try db.query("SELECT * FROM notes WHERE id = ?", bindings: [.text(id)])
            return rows.first.flatMap(Self.row)
        }
    }

    public func allRows() throws -> [NoteRow] {
        try lock.withLock {
            try db.query("SELECT * FROM notes ORDER BY created DESC, id DESC").compactMap(Self.row)
        }
    }

    public func search(_ query: String) throws -> [NoteRow] {
        guard let match = Self.matchExpression(query) else { return [] }
        return lock.withLock {
            do {
                return try db.query("""
                SELECT notes.* FROM notes
                JOIN notes_fts ON notes.rowid = notes_fts.rowid
                WHERE notes_fts MATCH ?
                ORDER BY notes.created DESC, notes.id DESC
                """, bindings: [.text(match)]).compactMap(Self.row)
            } catch {
                return []
            }
        }
    }

    public func removeAll() throws {
        try lock.withLock {
            try db.execute("DELETE FROM notes;")
        }
    }

    public func remove(id: String) throws {
        try lock.withLock {
            try db.run("DELETE FROM notes WHERE id = ?", bindings: [.text(id)])
        }
    }

    static func matchExpression(_ query: String) -> String? {
        let tokens = query.split { character in
            character.isWhitespace || character.isPunctuation
        }.map(String.init).filter { !$0.isEmpty }
        if tokens.isEmpty { return nil }
        return tokens.map { token in
            "\"\(token.replacingOccurrences(of: "\"", with: ""))\""
        }.joined(separator: " ")
    }

    private static func row(_ values: [String: SQLiteValue]) -> NoteRow? {
        guard let id = values["id"]?.textValue, let path = values["path"]?.textValue else { return nil }
        let createdMillis = values["created"]?.int ?? 0
        return NoteRow(
            id: id,
            path: path,
            title: values["title"]?.textValue ?? "",
            folder: values["folder"]?.textValue ?? "",
            kind: values["kind"]?.textValue ?? "written",
            created: Date(timeIntervalSince1970: Double(createdMillis) / 1000),
            duration: values["duration"]?.int.map { Int($0) },
            hasSummary: (values["has_summary"]?.int ?? 0) != 0,
            body: values["body"]?.textValue ?? "",
            localMtime: values["local_mtime"]?.int ?? 0,
            syncedMtime: values["synced_mtime"]?.int,
            driveId: values["drive_id"]?.textValue,
            driveRev: values["drive_rev"]?.textValue,
            phoneOnly: (values["phone_only"]?.int ?? 0) != 0
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
