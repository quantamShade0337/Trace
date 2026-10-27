import Foundation
import SQLite3

struct HistoryEntry: Identifiable, Codable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case connections = "Connections", trace = "Traceroute", diagnostic = "Diagnostics" }
    let id: UUID
    let date: Date
    let kind: Kind
    let title: String
    let detail: String
    init(id: UUID = UUID(), date: Date = .now, kind: Kind, title: String, detail: String) {
        self.id = id; self.date = date; self.kind = kind; self.title = title; self.detail = Self.boundedText(detail)
    }
    private static func boundedText(_ value: String) -> String {
        var data = Data(value.utf8.prefix(262_144))
        while !data.isEmpty {
            if let valid = String(data: data, encoding: .utf8) { return valid }
            data.removeLast()
        }
        return ""
    }
}

/// The SQLite handle is scoped to each actor operation, never shared across threads or retained by views.
actor HistoryStore {
    let url: URL
    init(url: URL) { self.url = url }

    private func withDatabase<T>(_ action: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            throw InspectorError.storage("Could not open local history. Check available disk space and folder permissions.")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)
        try execute("PRAGMA auto_vacuum=INCREMENTAL", db: db)
        try execute("CREATE TABLE IF NOT EXISTS history (id TEXT PRIMARY KEY, date REAL NOT NULL, kind TEXT NOT NULL, payload BLOB NOT NULL)", db: db)
        try execute("CREATE INDEX IF NOT EXISTS history_date ON history(date)", db: db)
        try execute("PRAGMA secure_delete=ON", db: db)
        return try action(db)
    }

    private func execute(_ sql: String, db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw InspectorError.storage(String(cString: sqlite3_errmsg(db)))
        }
    }

    func append(_ entry: HistoryEntry, retentionDays: Int, limit: Int = 2000, now: Date = .now) throws {
        try withDatabase { db in
            try execute("BEGIN IMMEDIATE", db: db)
            do {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO history VALUES (?, ?, ?, ?)", -1, &statement, nil) == SQLITE_OK,
                      let statement else { throw InspectorError.storage("Could not prepare history update.") }
                defer { sqlite3_finalize(statement) }
                let payload = try JSONEncoder().encode(entry)
                let status = entry.id.uuidString.withCString { id in
                    entry.kind.rawValue.withCString { kind in
                        payload.withUnsafeBytes { bytes in
                            sqlite3_bind_text(statement, 1, id, -1, nil)
                            sqlite3_bind_double(statement, 2, entry.date.timeIntervalSince1970)
                            sqlite3_bind_text(statement, 3, kind, -1, nil)
                            sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), nil)
                            return sqlite3_step(statement)
                        }
                    }
                }
                guard status == SQLITE_DONE else { throw InspectorError.storage("Could not save history. Check available disk space.") }
                try prune(db: db, retentionDays: retentionDays, limit: limit, now: now)
                try execute("COMMIT", db: db)
            } catch {
                try? execute("ROLLBACK", db: db)
                throw error
            }
        }
    }

    private func prune(db: OpaquePointer, retentionDays: Int, limit: Int, now: Date) throws {
        let cutoff = now.addingTimeInterval(-Double(max(1, min(retentionDays, 30))) * 86_400).timeIntervalSince1970
        try execute("DELETE FROM history WHERE date < \(cutoff)", db: db)
        try execute("DELETE FROM history WHERE id IN (SELECT id FROM (SELECT id, SUM(LENGTH(payload)) OVER (ORDER BY date DESC, id) AS total FROM history) WHERE total > 33554432)", db: db)
        try execute("DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY date DESC, id LIMIT \(max(0, min(limit, 2000))))", db: db)
    }

    func load(retentionDays: Int = 7, now: Date = .now) throws -> [HistoryEntry] {
        try withDatabase { db in
            try prune(db: db, retentionDays: retentionDays, limit: 2000, now: now)
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT payload FROM history ORDER BY date DESC LIMIT 2000", -1, &statement, nil) == SQLITE_OK,
                  let statement else { throw InspectorError.storage("Could not read local history.") }
            defer { sqlite3_finalize(statement) }
            var entries: [HistoryEntry] = []
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW {
                if let bytes = sqlite3_column_blob(statement, 0) {
                    let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
                    entries.append(try JSONDecoder().decode(HistoryEntry.self, from: data))
                }
                result = sqlite3_step(statement)
            }
            guard result == SQLITE_DONE else { throw InspectorError.storage("Reading history failed.") }
            return entries
        }
    }

    func deleteAll() throws {
        try withDatabase { db in
            try execute("DELETE FROM history", db: db)
            try execute("VACUUM", db: db)
        }
    }
}
