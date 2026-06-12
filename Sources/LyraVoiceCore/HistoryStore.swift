import Foundation
import SQLite3

public struct DictationEntry: Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let modelID: String
    public let durationSeconds: Double
    public let processingSeconds: Double
    /// Финальный текст после полировки (то, что вставляется/копируется по умолчанию).
    public let text: String
    /// Сырой («живой») текст до AI-правки. `nil` — для старых записей и когда
    /// полировка была выключена (тогда отменять нечего). Питает «Undo AI Edit».
    public let rawText: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        modelID: String,
        durationSeconds: Double,
        processingSeconds: Double,
        text: String,
        rawText: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modelID = modelID
        self.durationSeconds = durationSeconds
        self.processingSeconds = processingSeconds
        self.text = text
        self.rawText = rawText
    }
}

/// Хранилище истории диктовок на SQLite.
/// Публичный API идентичен старому JSONL-варианту; при первом запуске
/// автоматически мигрирует данные из `history.jsonl` (если файл есть).
public final class HistoryStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "ai.lyra.history-store", qos: .userInitiated)

    /// Срок хранения записей в днях. 0 = хранить всё.
    public var retentionDays: Int

    // MARK: - Init

    public init(directory: URL, retentionDays: Int = 7) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.retentionDays = retentionDays
        let dbURL = directory.appendingPathComponent("history.db")
        try openDB(at: dbURL)
        try createSchema()
        migrateSchema()
        // Однократная миграция из JSONL
        let jsonlURL = directory.appendingPathComponent("history.jsonl")
        try? migrateFromJSONL(at: jsonlURL, directory: directory)
        try? pruneOld()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Public API

    public func append(_ entry: DictationEntry) throws {
        try queue.sync {
            let sql = """
                INSERT OR REPLACE INTO dictations
                    (id, created_at, model_id, duration_seconds, processing_seconds, text, raw_text)
                VALUES (?, ?, ?, ?, ?, ?, ?);
                """
            var stmt: OpaquePointer?
            try prepare(sql, &stmt)
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, entry.createdAt.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, entry.modelID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, entry.durationSeconds)
            sqlite3_bind_double(stmt, 5, entry.processingSeconds)
            sqlite3_bind_text(stmt, 6, entry.text, -1, SQLITE_TRANSIENT)
            if let raw = entry.rawText {
                sqlite3_bind_text(stmt, 7, raw, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            try step(stmt)
            try pruneOldLocked()
        }
    }

    /// Последние `limit` записей, новые сверху.
    public func recent(limit: Int) throws -> [DictationEntry] {
        guard limit > 0 else { return [] }
        return try queue.sync {
            try fetch("SELECT * FROM dictations ORDER BY created_at DESC LIMIT \(limit);")
        }
    }

    /// Все записи, новые сверху.
    public func all() throws -> [DictationEntry] {
        try queue.sync {
            try fetch("SELECT * FROM dictations ORDER BY created_at DESC;")
        }
    }

    /// Полнотекстовый поиск (LIKE, case-insensitive). Пустая строка — все записи.
    public func search(query: String, limit: Int = 500) throws -> [DictationEntry] {
        try queue.sync {
            guard !query.isEmpty else {
                return try fetch("SELECT * FROM dictations ORDER BY created_at DESC LIMIT \(limit);")
            }
            let pattern = "%\(query.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
            let sql = "SELECT * FROM dictations WHERE text LIKE ? ESCAPE '\\' ORDER BY created_at DESC LIMIT \(limit);"
            var stmt: OpaquePointer?
            try prepare(sql, &stmt)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
            return try rows(from: stmt)
        }
    }

    public func delete(id: UUID) throws {
        try queue.sync {
            var stmt: OpaquePointer?
            try prepare("DELETE FROM dictations WHERE id = ?;", &stmt)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            try step(stmt)
        }
    }

    public func clear() throws {
        try queue.sync {
            try exec("DELETE FROM dictations;")
        }
    }

    public func pruneOld() throws {
        try queue.sync { try pruneOldLocked() }
    }

    // MARK: - Private helpers

    private func openDB(at url: URL) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK {
            throw HistoryStoreError.openFailed(dbError())
        }
        // WAL-режим: параллельные чтения не блокируют запись.
        _ = sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }

    private func createSchema() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS dictations (
                id                  TEXT    PRIMARY KEY,
                created_at          REAL    NOT NULL,
                model_id            TEXT    NOT NULL DEFAULT '',
                duration_seconds    REAL    NOT NULL DEFAULT 0,
                processing_seconds  REAL    NOT NULL DEFAULT 0,
                text                TEXT    NOT NULL DEFAULT ''
            );
            CREATE INDEX IF NOT EXISTS idx_created_at ON dictations(created_at DESC);
            """)
    }

    /// Доращивание схемы для существующих БД. `raw_text` появилась позже —
    /// добавляем колонку, если её ещё нет (повторный ALTER даст ошибку
    /// «duplicate column» — она безопасно игнорируется). Колонка всегда
    /// оказывается последней (индекс 6) и для свежих, и для мигрированных БД.
    private func migrateSchema() {
        _ = sqlite3_exec(db, "ALTER TABLE dictations ADD COLUMN raw_text TEXT;", nil, nil, nil)
    }

    private func pruneOldLocked() throws {
        guard retentionDays > 0 else { return }
        let cutoff = Calendar.current
            .date(byAdding: .day, value: -retentionDays, to: Date())!
            .timeIntervalSince1970
        var stmt: OpaquePointer?
        try prepare("DELETE FROM dictations WHERE created_at < ?;", &stmt)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, cutoff)
        try step(stmt)
    }

    private func fetch(_ sql: String) throws -> [DictationEntry] {
        var stmt: OpaquePointer?
        try prepare(sql, &stmt)
        defer { sqlite3_finalize(stmt) }
        return try rows(from: stmt)
    }

    private func rows(from stmt: OpaquePointer?) throws -> [DictationEntry] {
        var result: [DictationEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idStr   = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
                let id      = UUID(uuidString: idStr)
            else { continue }
            let createdAt         = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let modelID           = sqlite3_column_text(stmt, 2).map({ String(cString: $0) }) ?? ""
            let durationSeconds   = sqlite3_column_double(stmt, 3)
            let processingSeconds = sqlite3_column_double(stmt, 4)
            let text              = sqlite3_column_text(stmt, 5).map({ String(cString: $0) }) ?? ""
            // raw_text (индекс 6) — последняя колонка после миграции; NULL → nil.
            let rawText           = sqlite3_column_text(stmt, 6).map({ String(cString: $0) })
            result.append(DictationEntry(
                id: id,
                createdAt: createdAt,
                modelID: modelID,
                durationSeconds: durationSeconds,
                processingSeconds: processingSeconds,
                text: text,
                rawText: rawText
            ))
        }
        return result
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw HistoryStoreError.execFailed(msg)
        }
    }

    private func prepare(_ sql: String, _ stmt: inout OpaquePointer?) throws {
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw HistoryStoreError.prepareFailed(dbError())
        }
    }

    private func step(_ stmt: OpaquePointer?) throws {
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw HistoryStoreError.stepFailed(dbError())
        }
    }

    private func dbError() -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no db"
    }

    // MARK: - JSONL миграция

    private func migrateFromJSONL(at jsonlURL: URL, directory: URL) throws {
        guard FileManager.default.fileExists(atPath: jsonlURL.path) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try Data(contentsOf: jsonlURL)
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            try? FileManager.default.moveItem(at: jsonlURL, to: jsonlURL.appendingPathExtension("migrated"))
            return
        }

        // Старый JSONL хранит text/rawText отдельно; структура DictationEntry может не совпадать.
        // Используем гибкий разбор через словарь.
        struct LegacyEntry: Decodable {
            let id: UUID?
            let createdAt: Date?
            let modelID: String?
            let model: String?
            let durationSeconds: Double?
            let processingSeconds: Double?
            let text: String?
            let rawText: String?

            private enum CodingKeys: String, CodingKey {
                case id, createdAt, modelID, model
                case durationSeconds, processingSeconds
                case text, rawText
            }
        }

        var migrated = 0
        var stmt: OpaquePointer?
        let sql = """
            INSERT OR IGNORE INTO dictations
                (id, created_at, model_id, duration_seconds, processing_seconds, text, raw_text)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
        try prepare(sql, &stmt)
        defer { sqlite3_finalize(stmt) }

        for line in text.split(separator: "\n") {
            guard let lineData = String(line).data(using: .utf8),
                  let entry = try? decoder.decode(LegacyEntry.self, from: lineData) else { continue }
            let id = entry.id ?? UUID()
            let createdAt = entry.createdAt ?? Date()
            let modelID = entry.modelID ?? entry.model ?? "unknown"
            let duration = entry.durationSeconds ?? 0
            let processing = entry.processingSeconds ?? 0
            let finalText = entry.text ?? entry.rawText ?? ""
            guard !finalText.isEmpty else { continue }

            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, createdAt.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, modelID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, duration)
            sqlite3_bind_double(stmt, 5, processing)
            sqlite3_bind_text(stmt, 6, finalText, -1, SQLITE_TRANSIENT)
            // Сырой текст из старого JSONL, если был и отличается от финального.
            if let raw = entry.rawText, !raw.isEmpty, raw != finalText {
                sqlite3_bind_text(stmt, 7, raw, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_step(stmt)
            migrated += 1
        }

        print("[LyraVoice] history-migrate: jsonl→sqlite migrated=\(migrated)")
        // Переименовываем, не удаляем — безопасно.
        try? FileManager.default.moveItem(at: jsonlURL, to: jsonlURL.appendingPathExtension("migrated"))
    }
}

public enum HistoryStoreError: Error, Equatable {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    // Оставляем для обратной совместимости с существующими catch.
    case encodingFailed
    case decodingFailed
}

// Нужен для `sqlite3_bind_text` с SQLITE_TRANSIENT
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
