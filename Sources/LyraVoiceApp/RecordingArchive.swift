import Foundation
import LyraVoiceCore

/// Сохраняет пары «записанный звук + распознанный текст» в локальный корпус
/// `~/Library/Application Support/LyraVoice/Recordings/` для настройки качества
/// распознавания (подбор VAD/анти-повторов, постобработка, замеры «до/после»).
///
/// Включается настройкой `AppSettings.saveRecordings` (по умолчанию выключено,
/// ради приватности). Никуда не отправляет — только локальный диск.
enum RecordingArchive {
    /// Папка корпуса.
    static func directory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(AppBrand.applicationSupportDirectoryName)/Recordings",
                                    isDirectory: true)
    }

    /// Скопировать WAV в корпус и дописать метаданные в `manifest.jsonl`.
    /// Вызывать ДО удаления временной записи. Ошибки не критичны — только лог.
    static func save(
        audioURL: URL,
        text: String,
        rawText: String,
        modelID: String,
        language: String,
        durationSeconds: Double,
        processingSeconds: Double
    ) {
        let fm = FileManager.default
        let dir = directory()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            DiagnosticsLog.write("recording archive: mkdir failed \(error.localizedDescription)")
            return
        }

        let base = "\(stampFormatter.string(from: Date()))-\(UUID().uuidString.prefix(8))"
        let destination = dir.appendingPathComponent("\(base).wav")
        do {
            try fm.copyItem(at: audioURL, to: destination)
        } catch {
            DiagnosticsLog.write("recording archive: copy failed \(error.localizedDescription)")
            return
        }

        // Одна строка JSONL на запись — удобно для последующего разбора корпуса.
        let entry: [String: Any] = [
            "file": destination.lastPathComponent,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "model": modelID,
            "language": language,
            "durationSeconds": durationSeconds,
            "processingSeconds": processingSeconds,
            "rawText": rawText,           // сырой результат whisper (до полировки)
            "text": text                  // финальный текст (после полировки)
        ]
        appendManifest(entry, in: dir)
        DiagnosticsLog.write("recording archive: saved \(destination.lastPathComponent) dur=\(String(format: "%.1f", durationSeconds))s")
    }

    /// Удаляет записи (WAV + строки манифеста) старше `retention.days`. `forever` — no-op.
    /// Дату записи берём из `createdAt` манифеста (ISO8601); ошибки — не критичны, только лог.
    static func pruneOldRecordings(retention: RecordingsRetentionPeriod) {
        guard let days = retention.days else { return }
        let fm = FileManager.default
        let dir = directory()
        let manifest = dir.appendingPathComponent("manifest.jsonl")
        guard let data = fm.contents(atPath: manifest.path),
              let content = String(data: data, encoding: .utf8) else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let isoFormatter = ISO8601DateFormatter()
        var keptLines: [String] = []
        var removed = 0

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let createdAtString = json["createdAt"] as? String,
                  let createdAt = isoFormatter.date(from: createdAtString),
                  let file = json["file"] as? String else {
                keptLines.append(String(line))
                continue
            }
            if createdAt < cutoff {
                try? fm.removeItem(at: dir.appendingPathComponent(file))
                removed += 1
            } else {
                keptLines.append(String(line))
            }
        }

        guard removed > 0 else { return }
        let updated = keptLines.isEmpty ? "" : keptLines.joined(separator: "\n") + "\n"
        do {
            try updated.write(to: manifest, atomically: true, encoding: .utf8)
            DiagnosticsLog.write("recording archive: pruned \(removed) recordings older than \(days)d")
        } catch {
            DiagnosticsLog.write("recording archive: prune write failed \(error.localizedDescription)")
        }
    }

    private static func appendManifest(_ entry: [String: Any], in dir: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        let line = (json + "\n").data(using: .utf8) ?? Data()
        let manifest = dir.appendingPathComponent("manifest.jsonl")
        if let handle = try? FileHandle(forWritingTo: manifest) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(line)
        } else {
            try? line.write(to: manifest)
        }
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
