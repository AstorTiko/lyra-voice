import Foundation
import LyraVoiceCore

/// Управляет жизненным циклом `llama-server` (llama.cpp) для локальной
/// LLM-полировки. Сервер поднимается один раз и держит модель в памяти —
/// полировка идёт быстрым HTTP-запросом, без перезагрузки модели на каждую диктовку.
///
/// Запускаем, когда выбран уровень «Красиво» и модель скачана; гасим при
/// переключении на другой уровень и при выходе из приложения.
@MainActor
final class LocalLLMServer {
    /// Нестандартный порт, чтобы не конфликтовать с дефолтным llama-server (8080).
    static let port = 8757

    private var process: Process?
    private var logHandle: FileHandle?

    /// Запущен ли наш процесс сервера (не гарантирует, что модель уже прогрелась —
    /// это проверяет polisher по факту запроса с фолбэком на правила).
    private(set) var isRunning = false

    var chatEndpoint: URL {
        URL(string: "http://127.0.0.1:\(Self.port)/v1/chat/completions")!
    }

    /// Поднять сервер, если выбран localLLM, модель скачана и сервер ещё не работает.
    func ensureRunning(for settings: AppSettings) {
        guard settings.polishLevel == .localLLM else { return }
        guard !isRunning else { return }

        let model = LocalLLMModel.default
        guard model.isDownloaded(inModelDirectory: settings.modelDirectoryPath) else {
            DiagnosticsLog.write("llm server skip: model not downloaded \(model.fileName)")
            return
        }
        let binaryPath = settings.localLLMServerBinaryPath
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            DiagnosticsLog.write("llm server skip: binary missing at \(binaryPath)")
            return
        }

        start(binaryPath: binaryPath, modelPath: model.fileURL(inModelDirectory: settings.modelDirectoryPath).path)
    }

    func stop() {
        guard let process, isRunning else { return }
        DiagnosticsLog.write("llm server stopping pid=\(process.processIdentifier)")
        process.terminate()
        self.process = nil
        isRunning = false
        try? logHandle?.close()
        logHandle = nil
    }

    private func start(binaryPath: String, modelPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "-m", modelPath,
            "--host", "127.0.0.1",
            "--port", String(Self.port),
            "-c", "4096",
            "-ngl", "99"
        ]

        // Вывод сервера — в лог-файл: пайпы без чтения переполнятся и заблокируют процесс.
        let logURL = Self.logFileURL()
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            process.standardOutput = handle
            process.standardError = handle
            logHandle = handle
        }

        process.terminationHandler = { finished in
            let code = finished.terminationStatus
            Task { @MainActor in
                DiagnosticsLog.write("llm server exited code=\(code)")
                self.isRunning = false
                self.process = nil
            }
        }

        do {
            try process.run()
            self.process = process
            isRunning = true
            DiagnosticsLog.write("llm server started pid=\(process.processIdentifier) port=\(Self.port) model=\((modelPath as NSString).lastPathComponent)")
        } catch {
            DiagnosticsLog.write("llm server start failed: \(error.localizedDescription)")
            isRunning = false
            try? logHandle?.close()
            logHandle = nil
        }
    }

    private static func logFileURL() -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(AppBrand.applicationSupportDirectoryName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("llama-server.log")
    }
}
