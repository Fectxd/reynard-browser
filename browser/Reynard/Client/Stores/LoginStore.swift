//
//  LoginStore.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  SQLite-backed store for saved logins (HTTP authentication credentials and
//  web-form logins). Modelled on `SitePermissionStore`: a single serial queue
//  owns the connection and every statement runs on it.
//
//  Multiple rows per origin are expected — that is what powers the
//  multi-account picker for HTTP authentication (e.g. a router's LuCI page
//  with several accounts).
//
//  Private browsing: the store itself is session-agnostic. Callers (the auth /
//  login-save prompts) must NOT read from or write to it while the requesting
//  session is in private mode, so that private-mode credentials are never
//  persisted.
//

import Foundation
import SQLite3

/// How a stored login is used.
enum LoginKind: String {
    /// A web-form login saved through Gecko's `Autocomplete:Save:Login` prompt.
    case form = "form"
    /// An HTTP authentication (Basic / Digest) credential.
    case http = "http"
}

/// A single saved login row.
struct LoginRecord {
    let id: Int64
    let guid: String
    /// The full origin the login belongs to, e.g. `https://192.168.1.1:80`.
    let origin: String
    /// Normalized host derived from `origin`, used for matching.
    let host: String
    /// Origin of the form that submitted the login (form logins only).
    let formActionOrigin: String?
    /// HTTP authentication realm (HTTP logins only).
    let httpRealm: String?
    let kind: LoginKind
    let username: String
    let password: String
    let createdAt: Date
    let lastUsedAt: Date?
    let timesUsed: Int
}

final class LoginStore {
    static let shared = LoginStore()

    /// Posted (on the main queue) whenever the stored logins change.
    ///
    /// A raw name is used deliberately so this file does not have to declare a
    /// `Notification.Name` extension while a parallel change owns that file.
    static let didChangeNotification = Notification.Name("LoginStore.DidChange")

    private struct StorageURLs {
        let directoryURL: URL
        let databaseURL: URL
    }

    private let fileManager: FileManager
    private let storage: StorageURLs
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.LoginStore.Queue", qos: .utility)
    private var database: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: - Lifecycle

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        guard let applicationSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory is unavailable")
        }

        let directoryURL = applicationSupportDirectoryURL
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("Logins", isDirectory: true)

        self.storage = StorageURLs(
            directoryURL: directoryURL,
            databaseURL: directoryURL.appendingPathComponent("Logins", isDirectory: false)
        )

        stateQueue.sync {
            prepareStorageLocked()
            openDatabaseLocked()
            configureDatabaseLocked()
            createSchemaLocked()
            migrateSchemaLocked()
        }
    }

    deinit {
        stateQueue.sync {
            guard let database else {
                return
            }

            sqlite3_close(database)
            self.database = nil
        }
    }

    // MARK: - Reads

    /// Every saved login, ordered by host then username (used by Settings).
    func allLogins() -> [LoginRecord] {
        return stateQueue.sync {
            recordsLocked(whereClause: nil, bindings: [])
        }
    }

    /// Saved logins whose normalized host matches `origin`.
    ///
    /// Handles both a full origin (`https://example.com:443`) and a bare host.
    func logins(forOrigin origin: String) -> [LoginRecord] {
        let host = Self.normalizedHost(forOrigin: origin)
        guard !host.isEmpty else {
            return []
        }

        return stateQueue.sync {
            recordsLocked(whereClause: "host = ?", bindings: [host])
        }
    }

    /// Saved logins for a host filtered by kind.
    func logins(forOrigin origin: String, kind: LoginKind) -> [LoginRecord] {
        let host = Self.normalizedHost(forOrigin: origin)
        guard !host.isEmpty else {
            return []
        }

        return stateQueue.sync {
            recordsLocked(whereClause: "host = ? AND kind = ?", bindings: [host, kind.rawValue])
        }
    }

    func count() -> Int {
        return stateQueue.sync {
            guard let statement = prepareStatementLocked("SELECT COUNT(*) FROM logins;") else {
                return 0
            }

            defer {
                sqlite3_finalize(statement)
            }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    /// The normalized host used for matching, so callers can group/compare.
    static func normalizedHost(forOrigin origin: String) -> String {
        if let host = URLUtils.normalizedHost(fromRawURI: origin) {
            return host
        }

        return URLUtils.normalizedHost(origin) ?? ""
    }

    // MARK: - Writes

    /// Inserts a new login, or updates the password of an existing row with the
    /// same kind / origin / realm / username. Returns the stored record.
    @discardableResult
    func save(
        origin: String,
        formActionOrigin: String? = nil,
        httpRealm: String? = nil,
        kind: LoginKind,
        username: String,
        password: String,
        guid: String? = nil
    ) -> LoginRecord? {
        let origin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !origin.isEmpty else {
            return nil
        }

        let host = Self.normalizedHost(forOrigin: origin)
        guard !host.isEmpty else {
            return nil
        }

        return stateQueue.sync {
            let realm = httpRealm?.trimmingCharacters(in: .whitespacesAndNewlines)
            let realmBinding = (realm?.isEmpty == false) ? realm! : ""

            if let existing = recordLocked(kind: kind, origin: origin, username: username, realm: realmBinding),
               let updated = updateLocked(
                   id: existing.id,
                   origin: origin,
                   host: host,
                   formActionOrigin: formActionOrigin,
                   httpRealm: realm,
                   kind: kind,
                   username: username,
                   password: password
               ) {
                postDidChange()
                return updated
            }

            let now = Date()
            let resolvedGUID = (guid?.isEmpty == false) ? guid! : UUID().uuidString

            guard let statement = prepareStatementLocked(
                """
                INSERT INTO logins
                    (guid, origin, host, form_action_origin, http_realm, kind, username, password, created_at, last_used_at, times_used)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            ) else {
                return nil
            }

            defer {
                sqlite3_finalize(statement)
            }

            bind(resolvedGUID, to: statement, at: 1)
            bind(origin, to: statement, at: 2)
            bind(host, to: statement, at: 3)
            bind(formActionOrigin, to: statement, at: 4)
            bind(realm, to: statement, at: 5)
            bind(kind.rawValue, to: statement, at: 6)
            bind(username, to: statement, at: 7)
            bind(password, to: statement, at: 8)
            sqlite3_bind_double(statement, 9, now.timeIntervalSince1970)
            sqlite3_bind_null(statement, 10)
            sqlite3_bind_int64(statement, 11, 0)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                return nil
            }

            let identifier = sqlite3_last_insert_rowid(database)
            postDidChange()
            return recordLocked(id: identifier)
        }
    }

    /// Replaces every field of an existing row.
    @discardableResult
    func update(
        id: Int64,
        origin: String,
        formActionOrigin: String? = nil,
        httpRealm: String? = nil,
        kind: LoginKind,
        username: String,
        password: String
    ) -> LoginRecord? {
        let origin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !origin.isEmpty else {
            return nil
        }

        let host = Self.normalizedHost(forOrigin: origin)
        guard !host.isEmpty else {
            return nil
        }

        let result: LoginRecord? = stateQueue.sync {
            let updated = updateLocked(
                id: id,
                origin: origin,
                host: host,
                formActionOrigin: formActionOrigin,
                httpRealm: httpRealm,
                kind: kind,
                username: username,
                password: password
            )
            if updated != nil {
                postDidChange()
            }
            return updated
        }

        return result
    }

    func delete(id: Int64) {
        stateQueue.sync {
            guard let statement = prepareStatementLocked("DELETE FROM logins WHERE id = ?;") else {
                return
            }

            defer {
                sqlite3_finalize(statement)
            }

            sqlite3_bind_int64(statement, 1, id)
            _ = sqlite3_step(statement)
            postDidChange()
        }
    }

    func removeAll() {
        stateQueue.sync {
            _ = executeLocked("DELETE FROM logins;")
            postDidChange()
        }
    }

    /// Records that a stored login was just used.
    func markUsed(id: Int64) {
        stateQueue.sync {
            guard let statement = prepareStatementLocked(
                "UPDATE logins SET last_used_at = ?, times_used = times_used + 1 WHERE id = ?;"
            ) else {
                return
            }

            defer {
                sqlite3_finalize(statement)
            }

            sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
            sqlite3_bind_int64(statement, 2, id)
            _ = sqlite3_step(statement)
        }
    }

    // MARK: - Storage

    private func prepareStorageLocked() {
        try? fileManager.createDirectory(at: storage.directoryURL, withIntermediateDirectories: true)
    }

    private func openDatabaseLocked() {
        guard database == nil else {
            return
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(storage.databaseURL.path, &database, flags, nil) == SQLITE_OK else {
            if let database {
                sqlite3_close(database)
            }
            assertionFailure("Failed to open Logins database")
            return
        }

        self.database = database
    }

    private func configureDatabaseLocked() {
        guard database != nil else {
            return
        }

        _ = executeLocked("PRAGMA foreign_keys = ON;")
        _ = executeLocked("PRAGMA journal_mode = WAL;")
        _ = executeLocked("PRAGMA synchronous = NORMAL;")
        _ = executeLocked("PRAGMA temp_store = MEMORY;")
        sqlite3_busy_timeout(database, 2_500)
    }

    private func createSchemaLocked() {
        let sql = """
        CREATE TABLE IF NOT EXISTS logins (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            guid TEXT NOT NULL,
            origin TEXT NOT NULL,
            host TEXT NOT NULL DEFAULT '',
            form_action_origin TEXT,
            http_realm TEXT,
            kind TEXT NOT NULL,
            username TEXT NOT NULL DEFAULT '',
            password TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL,
            last_used_at REAL,
            times_used INTEGER NOT NULL DEFAULT 0
        );

        CREATE INDEX IF NOT EXISTS idx_logins_host ON logins(host);
        CREATE INDEX IF NOT EXISTS idx_logins_origin ON logins(origin);
        CREATE INDEX IF NOT EXISTS idx_logins_kind ON logins(kind);
        """

        _ = executeLocked(sql)
    }

    // MARK: - Schema Migration

    private func migrateSchemaLocked() {
        // `host` was added so matching never has to parse origins inside SQL.
        // Existing rows (if any) are back-filled from `origin`.
        ensureColumnLocked(name: "host", table: "logins", definition: "TEXT NOT NULL DEFAULT ''")
        backfillHostsLocked()
    }

    private func ensureColumnLocked(name: String, table: String, definition: String) {
        guard let statement = prepareStatementLocked("PRAGMA table_info(\(table));") else {
            return
        }

        var hasColumn = false
        while sqlite3_step(statement) == SQLITE_ROW {
            if string(from: statement, at: 1) == name {
                hasColumn = true
                break
            }
        }
        sqlite3_finalize(statement)

        guard !hasColumn else {
            return
        }

        _ = executeLocked("ALTER TABLE \(table) ADD COLUMN \(name) \(definition);")
    }

    private func backfillHostsLocked() {
        guard let statement = prepareStatementLocked("SELECT id, origin FROM logins WHERE host = '';") else {
            return
        }

        var pending: [(Int64, String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            pending.append((sqlite3_column_int64(statement, 0), string(from: statement, at: 1)))
        }
        sqlite3_finalize(statement)

        for (identifier, origin) in pending {
            let host = Self.normalizedHost(forOrigin: origin)
            guard !host.isEmpty else {
                continue
            }

            guard let update = prepareStatementLocked("UPDATE logins SET host = ? WHERE id = ?;") else {
                continue
            }

            bind(host, to: update, at: 1)
            sqlite3_bind_int64(update, 2, identifier)
            _ = sqlite3_step(update)
            sqlite3_finalize(update)
        }
    }

    // MARK: - Record Queries

    private func recordLocked(id: Int64) -> LoginRecord? {
        return recordsLocked(whereClause: "id = ?", bindings: [id]).first
    }

    private func recordLocked(kind: LoginKind, origin: String, username: String, realm: String) -> LoginRecord? {
        return recordsLocked(
            whereClause: "kind = ? AND origin = ? AND username = ? AND ifnull(http_realm, '') = ?",
            bindings: [kind.rawValue, origin, username, realm]
        ).first
    }

    private func recordsLocked(whereClause: String?, bindings: [Any]) -> [LoginRecord] {
        var sql = """
        SELECT id, guid, origin, host, form_action_origin, http_realm, kind, username, password, created_at, last_used_at, times_used
        FROM logins
        """

        if let whereClause {
            sql += "\nWHERE \(whereClause)"
        }

        sql += "\nORDER BY host COLLATE NOCASE ASC, username COLLATE NOCASE ASC, id ASC;"

        guard let statement = prepareStatementLocked(sql) else {
            return []
        }

        defer {
            sqlite3_finalize(statement)
        }

        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            if let text = value as? String {
                bind(text, to: statement, at: index)
            } else if let number = value as? Int64 {
                sqlite3_bind_int64(statement, index, number)
            } else if let number = value as? Int {
                sqlite3_bind_int64(statement, index, Int64(number))
            }
        }

        var records: [LoginRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let record = record(from: statement) else {
                continue
            }
            records.append(record)
        }
        return records
    }

    private func record(from statement: OpaquePointer) -> LoginRecord? {
        let kindRaw = string(from: statement, at: 6)
        guard let kind = LoginKind(rawValue: kindRaw) else {
            return nil
        }

        let lastUsedValue = sqlite3_column_double(statement, 10)
        return LoginRecord(
            id: sqlite3_column_int64(statement, 0),
            guid: string(from: statement, at: 1),
            origin: string(from: statement, at: 2),
            host: string(from: statement, at: 3),
            formActionOrigin: optionalString(from: statement, at: 4),
            httpRealm: optionalString(from: statement, at: 5),
            kind: kind,
            username: string(from: statement, at: 7),
            password: string(from: statement, at: 8),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            lastUsedAt: lastUsedValue > 0 ? Date(timeIntervalSince1970: lastUsedValue) : nil,
            timesUsed: Int(sqlite3_column_int64(statement, 11))
        )
    }

    private func updateLocked(
        id: Int64,
        origin: String,
        host: String,
        formActionOrigin: String?,
        httpRealm: String?,
        kind: LoginKind,
        username: String,
        password: String
    ) -> LoginRecord? {
        guard let statement = prepareStatementLocked(
            """
            UPDATE logins
            SET origin = ?,
                host = ?,
                form_action_origin = ?,
                http_realm = ?,
                kind = ?,
                username = ?,
                password = ?
            WHERE id = ?;
            """
        ) else {
            return nil
        }

        defer {
            sqlite3_finalize(statement)
        }

        bind(origin, to: statement, at: 1)
        bind(host, to: statement, at: 2)
        bind(formActionOrigin, to: statement, at: 3)
        bind(httpRealm, to: statement, at: 4)
        bind(kind.rawValue, to: statement, at: 5)
        bind(username, to: statement, at: 6)
        bind(password, to: statement, at: 7)
        sqlite3_bind_int64(statement, 8, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            return nil
        }

        return recordLocked(id: id)
    }

    // MARK: - Notifications

    private func postDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: LoginStore.didChangeNotification, object: self)
        }
    }

    // MARK: - SQLite

    private func prepareStatementLocked(_ sql: String) -> OpaquePointer? {
        guard let database else {
            return nil
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            assertionFailure("Failed to prepare Logins SQL statement")
            return nil
        }

        return statement
    }

    private func executeLocked(_ sql: String) -> Bool {
        guard let database else {
            return false
        }

        return sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bind(_ text: String?, to statement: OpaquePointer, at index: Int32) {
        guard let text else {
            sqlite3_bind_null(statement, index)
            return
        }

        sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
    }

    private func string(from statement: OpaquePointer, at index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            return ""
        }

        return String(cString: cString)
    }

    private func optionalString(from statement: OpaquePointer, at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }

        return string(from: statement, at: index)
    }
}
