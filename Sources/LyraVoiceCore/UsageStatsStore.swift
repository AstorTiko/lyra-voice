import Foundation
import SQLite3

private let SQLITE_TRANSIENT_USAGE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Период для срезов статистики дашборда.
public enum UsagePeriod: String, CaseIterable, Equatable, Sendable {
    case day    // сегодня (текущий календарный день)
    case week   // последние 7 дней (включая сегодня)
    case month  // последние 30 дней (включая сегодня)

    /// Сколько календарных дней охватывает период (для оси графика).
    public var dayCount: Int {
        switch self {
        case .day:   return 1
        case .week:  return 7
        case .month: return 30
        }
    }
}

/// Агрегаты по одному календарному дню (для мини-графика активности).
public struct DailyUsage: Equatable, Sendable {
    public let day: Date            // начало дня (startOfDay)
    public let dictationCount: Int
    public let wordCount: Int
    public let durationSeconds: Double

    public init(day: Date, dictationCount: Int, wordCount: Int, durationSeconds: Double) {
        self.day = day
        self.dictationCount = dictationCount
        self.wordCount = wordCount
        self.durationSeconds = durationSeconds
    }
}

/// Срез статистики за выбранный период.
public struct UsagePeriodStats: Equatable, Sendable {
    public let period: UsagePeriod
    public let dictationCount: Int
    public let wordCount: Int
    public let durationSeconds: Double
    public let activeDays: Int          // дней с ≥1 диктовкой внутри периода
    public let sessionCount: Int        // запусков приложения внутри периода
    public let daily: [DailyUsage]      // по дню на каждый календарный день периода (zero-filled)

    public init(
        period: UsagePeriod,
        dictationCount: Int,
        wordCount: Int,
        durationSeconds: Double,
        activeDays: Int,
        sessionCount: Int,
        daily: [DailyUsage]
    ) {
        self.period = period
        self.dictationCount = dictationCount
        self.wordCount = wordCount
        self.durationSeconds = durationSeconds
        self.activeDays = activeDays
        self.sessionCount = sessionCount
        self.daily = daily
    }

    public static func empty(_ period: UsagePeriod) -> UsagePeriodStats {
        UsagePeriodStats(
            period: period,
            dictationCount: 0,
            wordCount: 0,
            durationSeconds: 0,
            activeDays: 0,
            sessionCount: 0,
            daily: []
        )
    }
}

public struct UsageDashboardSnapshot: Equatable, Sendable {
    public let lifetime: DictationUsageSummary
    public let periods: [UsagePeriodStats]
    public let currentStreak: Int
    public let longestStreak: Int

    public init(lifetime: DictationUsageSummary, periods: [UsagePeriodStats], currentStreak: Int, longestStreak: Int = 0) {
        self.lifetime = lifetime
        self.periods = periods
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
    }

    public static let empty = UsageDashboardSnapshot(
        lifetime: .empty,
        periods: UsagePeriod.allCases.map { .empty($0) },
        currentStreak: 0,
        longestStreak: 0
    )

    public func stats(for period: UsagePeriod) -> UsagePeriodStats {
        periods.first { $0.period == period } ?? .empty(period)
    }
}

public enum UsageStatsStoreError: Error, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case execFailed(String)
}

/// Накопительная статистика использования, НЕ зависящая от retention истории.
///
/// История (`HistoryStore`) урезается до `retentionDays`, поэтому считать по ней
/// «всего / за 30 дней» некорректно. Здесь события диктовок и запуски приложения
/// хранятся отдельно и никогда не прунятся — дашборд показывает честные тоталы и
/// периодные срезы (День / 7 дней / 30 дней) плюс активность (стрик, сессии).
public final class UsageStatsStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "ai.lyra.usage-stats-store", qos: .userInitiated)
    private let calendar: Calendar

    // MARK: - Init

    public init(directory: URL, calendar: Calendar = .current) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.calendar = calendar
        let dbURL = directory.appendingPathComponent("usage.db")
        try openDB(at: dbURL)
        try createSchema()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Запись событий

    /// Зафиксировать одну диктовку. `wordCount` считается вызывающей стороной
    /// (через `UsageStatsStore.wordCount(of:)`), чтобы не дублировать логику.
    public func recordDictation(
        wordCount: Int,
        durationSeconds: Double,
        modelID: String,
        at timestamp: Date = Date()
    ) throws {
        try queue.sync {
            let sql = """
                INSERT INTO usage_events (id, timestamp, word_count, duration_seconds, model_id)
                VALUES (?, ?, ?, ?, ?);
                """
            var stmt: OpaquePointer?
            try prepare(sql, &stmt)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, UUID().uuidString, -1, SQLITE_TRANSIENT_USAGE)
            sqlite3_bind_double(stmt, 2, timestamp.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 3, Int32(max(0, wordCount)))
            sqlite3_bind_double(stmt, 4, max(0, durationSeconds))
            sqlite3_bind_text(stmt, 5, modelID, -1, SQLITE_TRANSIENT_USAGE)
            try step(stmt)
        }
    }

    /// Зафиксировать запуск приложения (для счётчика сессий / активности).
    public func recordSession(at timestamp: Date = Date()) throws {
        try queue.sync {
            var stmt: OpaquePointer?
            try prepare("INSERT INTO app_sessions (id, started_at) VALUES (?, ?);", &stmt)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, UUID().uuidString, -1, SQLITE_TRANSIENT_USAGE)
            sqlite3_bind_double(stmt, 2, timestamp.timeIntervalSince1970)
            try step(stmt)
        }
    }

    /// Однократный бэкфилл из существующей истории, если таблица событий пуста.
    /// Чтобы у уже пользовавшихся приложением тоталы не обнулились при первом
    /// запуске после внедрения статистики. Возвращает число импортированных событий.
    @discardableResult
    public func backfillIfEmpty(from entries: [DictationEntry]) throws -> Int {
        try queue.sync {
            if try countLocked("SELECT COUNT(*) FROM usage_events;") > 0 { return 0 }
            guard !entries.isEmpty else { return 0 }
            try execLocked("BEGIN TRANSACTION;")
            do {
                for entry in entries {
                    var stmt: OpaquePointer?
                    try prepare("""
                        INSERT INTO usage_events (id, timestamp, word_count, duration_seconds, model_id)
                        VALUES (?, ?, ?, ?, ?);
                        """, &stmt)
                    sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT_USAGE)
                    sqlite3_bind_double(stmt, 2, entry.createdAt.timeIntervalSince1970)
                    sqlite3_bind_int(stmt, 3, Int32(Self.wordCount(of: entry.text)))
                    sqlite3_bind_double(stmt, 4, max(0, entry.durationSeconds))
                    sqlite3_bind_text(stmt, 5, entry.modelID, -1, SQLITE_TRANSIENT_USAGE)
                    try step(stmt)
                    sqlite3_finalize(stmt)
                }
                try execLocked("COMMIT;")
            } catch {
                try? execLocked("ROLLBACK;")
                throw error
            }
            return entries.count
        }
    }

    // MARK: - Чтение

    /// Тоталы за всё время (исправляет «дашборд считает только 7 дней»).
    public func lifetimeSummary() throws -> DictationUsageSummary {
        try queue.sync {
            var stmt: OpaquePointer?
            try prepare("SELECT COUNT(*), COALESCE(SUM(word_count), 0), COALESCE(SUM(duration_seconds), 0) FROM usage_events;", &stmt)
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return .empty }
            return DictationUsageSummary(
                dictationCount: Int(sqlite3_column_int(stmt, 0)),
                wordCount: Int(sqlite3_column_int(stmt, 1)),
                durationSeconds: sqlite3_column_double(stmt, 2)
            )
        }
    }

    /// Срез статистики за период с разбивкой по дням.
    public func stats(for period: UsagePeriod, now: Date = Date()) throws -> UsagePeriodStats {
        try queue.sync {
            let endOfToday = calendar.startOfDay(for: now)
            guard let start = calendar.date(byAdding: .day, value: -(period.dayCount - 1), to: endOfToday) else {
                return .empty(period)
            }
            // Верхняя граница — начало завтрашнего дня (полностью включаем сегодня).
            guard let upper = calendar.date(byAdding: .day, value: 1, to: endOfToday) else {
                return .empty(period)
            }

            let events = try fetchEventsLocked(from: start, to: upper)
            let sessionCount = try countLocked(
                "SELECT COUNT(*) FROM app_sessions WHERE started_at >= \(start.timeIntervalSince1970) AND started_at < \(upper.timeIntervalSince1970);"
            )

            // Zero-filled по дням.
            var buckets: [Date: (count: Int, words: Int, duration: Double)] = [:]
            for offset in 0..<period.dayCount {
                if let day = calendar.date(byAdding: .day, value: offset, to: start) {
                    buckets[day] = (0, 0, 0)
                }
            }
            for event in events {
                let day = calendar.startOfDay(for: event.timestamp)
                let prev = buckets[day] ?? (0, 0, 0)
                buckets[day] = (prev.count + 1, prev.words + event.wordCount, prev.duration + event.durationSeconds)
            }

            let daily = buckets.keys.sorted().map { day -> DailyUsage in
                let b = buckets[day]!
                return DailyUsage(day: day, dictationCount: b.count, wordCount: b.words, durationSeconds: b.duration)
            }

            let totalCount = events.count
            let totalWords = events.reduce(0) { $0 + $1.wordCount }
            let totalDuration = events.reduce(0) { $0 + $1.durationSeconds }
            let activeDays = buckets.values.filter { $0.count > 0 }.count

            return UsagePeriodStats(
                period: period,
                dictationCount: totalCount,
                wordCount: totalWords,
                durationSeconds: totalDuration,
                activeDays: activeDays,
                sessionCount: sessionCount,
                daily: daily
            )
        }
    }

    /// Текущий стрик — число подряд идущих дней с ≥1 диктовкой, заканчивая
    /// сегодня (или вчера, если сегодня ещё не диктовали — день не «сгорает»).
    public func currentStreak(now: Date = Date()) throws -> Int {
        try queue.sync {
            let activeDays = try activeDaySetLocked()
            guard !activeDays.isEmpty else { return 0 }
            let today = calendar.startOfDay(for: now)
            var cursor: Date
            if activeDays.contains(today) {
                cursor = today
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      activeDays.contains(yesterday) {
                cursor = yesterday
            } else {
                return 0
            }
            var streak = 0
            while activeDays.contains(cursor) {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            }
            return streak
        }
    }

    /// Самый длинный когда-либо набранный стрик подряд идущих дней с ≥1 диктовкой
    /// (не только текущий — исторический максимум, как «Longest streak» у Wispr Flow).
    public func longestStreak() throws -> Int {
        try queue.sync {
            let activeDays = try activeDaySetLocked()
            guard !activeDays.isEmpty else { return 0 }
            var longest = 0
            var current = 0
            var previousDay: Date?
            for day in activeDays.sorted() {
                if let previous = previousDay,
                   let expectedNext = calendar.date(byAdding: .day, value: 1, to: previous),
                   expectedNext == day {
                    current += 1
                } else {
                    current = 1
                }
                longest = max(longest, current)
                previousDay = day
            }
            return longest
        }
    }

    public func dashboardSnapshot(now: Date = Date()) throws -> UsageDashboardSnapshot {
        let lifetime = try lifetimeSummary()
        let periods = try UsagePeriod.allCases.map { period in
            try stats(for: period, now: now)
        }
        let streak = try currentStreak(now: now)
        let longest = try longestStreak()
        return UsageDashboardSnapshot(lifetime: lifetime, periods: periods, currentStreak: streak, longestStreak: longest)
    }

    // MARK: - Подсчёт слов (единая логика с DictationUsageSummary)

    public static func wordCount(of text: String) -> Int {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    // MARK: - Private (под queue)

    private struct StoredEvent {
        let timestamp: Date
        let wordCount: Int
        let durationSeconds: Double
    }

    private func fetchEventsLocked(from: Date, to upper: Date) throws -> [StoredEvent] {
        var stmt: OpaquePointer?
        try prepare("SELECT timestamp, word_count, duration_seconds FROM usage_events WHERE timestamp >= ? AND timestamp < ? ORDER BY timestamp ASC;", &stmt)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, upper.timeIntervalSince1970)
        var result: [StoredEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(StoredEvent(
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)),
                wordCount: Int(sqlite3_column_int(stmt, 1)),
                durationSeconds: sqlite3_column_double(stmt, 2)
            ))
        }
        return result
    }

    private func activeDaySetLocked() throws -> Set<Date> {
        var stmt: OpaquePointer?
        try prepare("SELECT timestamp FROM usage_events;", &stmt)
        defer { sqlite3_finalize(stmt) }
        var days: Set<Date> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let date = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
            days.insert(calendar.startOfDay(for: date))
        }
        return days
    }

    private func countLocked(_ sql: String) throws -> Int {
        var stmt: OpaquePointer?
        try prepare(sql, &stmt)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func openDB(at url: URL) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK {
            throw UsageStatsStoreError.openFailed(dbError())
        }
        _ = sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }

    private func createSchema() throws {
        try queue.sync {
            try execLocked("""
                CREATE TABLE IF NOT EXISTS usage_events (
                    id                TEXT    PRIMARY KEY,
                    timestamp         REAL    NOT NULL,
                    word_count        INTEGER NOT NULL DEFAULT 0,
                    duration_seconds  REAL    NOT NULL DEFAULT 0,
                    model_id          TEXT    NOT NULL DEFAULT ''
                );
                CREATE INDEX IF NOT EXISTS idx_usage_timestamp ON usage_events(timestamp);
                CREATE TABLE IF NOT EXISTS app_sessions (
                    id          TEXT    PRIMARY KEY,
                    started_at  REAL    NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_session_started ON app_sessions(started_at);
                """)
        }
    }

    private func execLocked(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw UsageStatsStoreError.execFailed(msg)
        }
    }

    private func prepare(_ sql: String, _ stmt: inout OpaquePointer?) throws {
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw UsageStatsStoreError.prepareFailed(dbError())
        }
    }

    private func step(_ stmt: OpaquePointer?) throws {
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw UsageStatsStoreError.stepFailed(dbError())
        }
    }

    private func dbError() -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no db"
    }
}
