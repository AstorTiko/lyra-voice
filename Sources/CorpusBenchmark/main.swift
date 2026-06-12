import Foundation
import LyraVoiceCore

/// A7: прогон корпуса `recordings/manifest.jsonl` через текущий RulePolisher
/// и сравнение с `text`, сохранённым в манифесте (старый пайплайн на момент записи).
/// Использование: `swift run CorpusBenchmark <путь к manifest.jsonl> <путь к отчёту .md>`

struct ManifestEntry: Decodable {
    let createdAt: String
    let durationSeconds: Double
    let file: String
    let rawText: String
    let text: String
}

let args = CommandLine.arguments
let manifestPath = args.count > 1 ? args[1] : "recordings/manifest.jsonl"
let reportPath = args.count > 2 ? args[2] : "app/benchmarks/real-corpus-2026-06-12.md"

guard let data = FileManager.default.contents(atPath: manifestPath) else {
    FileHandle.standardError.write("Не удалось открыть \(manifestPath)\n".data(using: .utf8)!)
    exit(1)
}

let lines = String(decoding: data, as: UTF8.self)
    .split(separator: "\n")
    .map(String.init)
    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

let decoder = JSONDecoder()
let polisher = RulePolisher()

var changed = 0
var unchanged = 0
var sameAsRaw = 0
var diffSamples: [(file: String, rawText: String, oldText: String, newText: String)] = []

let task = Task {
    for line in lines {
        guard let entry = try? decoder.decode(ManifestEntry.self, from: Data(line.utf8)) else { continue }
        // Реальный пайплайн (AppDelegate.swift) сначала склеивает whisper-переносы
        // строк через normalizeTranscriptNewlines, и только потом полирует.
        let normalizedRaw = TextPostProcessor.normalizeTranscriptNewlines(entry.rawText)
        let newText = try await polisher.polish(normalizedRaw)
        if newText == entry.text {
            unchanged += 1
        } else {
            changed += 1
            if diffSamples.count < 40 {
                diffSamples.append((entry.file, entry.rawText, entry.text, newText))
            }
        }
        if newText == entry.rawText {
            sameAsRaw += 1
        }
    }
}

try await task.value

var report = """
# Бенчмарк A7 — реальный корпус `recordings/` (2026-06-12)

Сравнение текущего `RulePolisher` (после правок A3–A6: расширенный список паразитов A5,
backtrack/команды, словарь, smart-context, нормализация дат/денег, списки) с текстом `text`,
сохранённым в `manifest.jsonl` на момент записи (старый пайплайн).

`rawText` — сырой вывод whisper.cpp на момент записи; A1 показал, что параметры ASR не менялись,
поэтому `rawText` остаётся валидной базой для сравнения пайплайна полировки.

## Сводка

- Всего записей: \(lines.count)
- Изменилось при текущей полировке: \(changed)
- Совпало со старым `text`: \(unchanged)
- Текущий результат равен необработанному `rawText` (полировка ничего не сделала): \(sameAsRaw)

## Примеры изменений (до 40)

"""

for sample in diffSamples {
    report += """

    ### \(sample.file)
    - **raw:** \(sample.rawText)
    - **было (manifest text):** \(sample.oldText)
    - **стало (текущий RulePolisher):** \(sample.newText)

    """
}

try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
print("Готово: \(changed) изменено, \(unchanged) совпало, отчёт: \(reportPath)")
