import Foundation

/// Находит исполняемые движки распознавания/полировки (`whisper-server`, `whisper-cli`,
/// `llama-server`).
///
/// В РЕЛИЗНОМ `.app` движки вшиты в `Contents/Helpers/bin` (см. `scripts/bundle-engines.sh`)
/// — используем их, чтобы приложение работало на любом Apple Silicon Mac БЕЗ homebrew.
/// В dev-сборке (свежий бандл без движков или `swift run`) откатываемся на `fallback`
/// (путь из настроек / homebrew). Модели приложение скачивает отдельно — они не вшиты.
enum EngineLocator {
    static func path(for name: String, fallback: String) -> String {
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/bin", isDirectory: true)
            .appendingPathComponent(name)
            .path
        if FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        return fallback
    }
}
