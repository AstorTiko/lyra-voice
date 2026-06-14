import Foundation
import LyraVoiceCore

/// Держит `whisper-server` живым между диктовками — исключает задержку загрузки модели
/// (~570 мс turbo / ~1730 мс large-v3 на каждый spawn `whisper-cli`).
///
/// Использование:
///   1. `WhisperServerService.shared.startIfNeeded(...)` при старте / смене модели.
///   2. `try WhisperServerService.shared.transcribe(...)` вместо WhisperCLITranscriber.
///   3. Вызывающий делает fallback на CLI если throws.
final class WhisperServerService: @unchecked Sendable {
    static let shared = WhisperServerService()
    private init() {}

    private let lock = NSLock()
    private var serverProcess: Process?
    private var currentModelPath: String?
    private let port = 56789

    /// Остановить сервер если молчание дольше этого времени. 0 = никогда.
    /// 30 минут: держим модель тёплой между диктовками (нужно для live-стриминга,
    /// мгновенного финального распознавания и — главное — чтобы распознавание шло БЕЗ
    /// VAD, который на CLI-пути иногда вырезает тихую/короткую речь целиком). Дольше
    /// тёплый сервер = реже падаем на CLI+VAD = меньше потерянных диктовок.
    var idleShutdownSeconds: Double = 30 * 60

    private var idleTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "ai.lyra.whisper-server.idle")

    var isRunning: Bool {
        lock.withLock { serverProcess?.isRunning == true }
    }

    // MARK: - Lifecycle

    /// Запустить сервер с указанной моделью.
    /// - Если уже запущен с той же моделью — ничего не делает, возвращает true.
    /// - Если модель сменилась — перезапускает.
    /// - Блокирует до готовности (≤ 8 с); если не поднялся — false без throw.
    @discardableResult
    func startIfNeeded(
        serverBinaryPath: String = EngineLocator.path(for: "whisper-server", fallback: "/opt/homebrew/bin/whisper-server"),
        modelURL: URL,
        threads: Int = WhisperCommand.recommendedThreadCount,
        beamSize: Int = 5,
        suppressNonSpeech: Bool = true
    ) -> Bool {
        let alreadyRunning = lock.withLock {
            serverProcess?.isRunning == true && currentModelPath == modelURL.path
        }
        if alreadyRunning { return true }

        stop()

        guard FileManager.default.fileExists(atPath: serverBinaryPath) else {
            DiagnosticsLog.write("warm-asr: binary missing \(serverBinaryPath)")
            return false
        }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            DiagnosticsLog.write("warm-asr: model missing \(modelURL.path)")
            return false
        }

        // NB: БЕЗ VAD намеренно. Сервер обслуживает и growing-window стриминг (короткие
        // 1.5–3 с окна), которому VAD вредит. VAD остаётся на CLI-fallback (vadEnabled).
        // `-sow` (--split-on-word): сервер переносит строки ТОЛЬКО на границе целых слов,
        // а не посреди слова. Без этого whisper рвёт слова переносом («перед\nелал»,
        // «зву\nку»), и постобработка иногда слепляла соседние слова — теперь переносы
        // всегда между словами и корректно склеиваются через пробел (фикс «слова слипаются»).
        var args = [
            "-m", modelURL.path,
            "-t", "\(threads)",
            "-bs", "\(beamSize)",
            "--port", "\(port)",
            "--host", "127.0.0.1",
            "-sow"
        ]
        if suppressNonSpeech { args.append("-sns") }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: serverBinaryPath)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            DiagnosticsLog.write("warm-asr: launch failed \(error.localizedDescription)")
            return false
        }

        lock.withLock {
            serverProcess = proc
            currentModelPath = modelURL.path
        }

        let ready = waitUntilReady(timeoutSeconds: 8)
        if ready {
            DiagnosticsLog.write("warm-asr: ready port=\(port) model=\(modelURL.lastPathComponent)")
            rescheduleIdleTimer()
        } else {
            DiagnosticsLog.write("warm-asr: timeout, falling back to CLI")
            stop()
        }
        return ready
    }

    func stop() {
        cancelIdleTimer()
        let proc: Process? = lock.withLock {
            let p = serverProcess
            serverProcess = nil
            currentModelPath = nil
            return p
        }
        guard let proc, proc.isRunning else { return }
        proc.terminate()
        proc.waitUntilExit()
        DiagnosticsLog.write("warm-asr: stopped")
    }

    // MARK: - Idle shutdown timer

    private func rescheduleIdleTimer() {
        guard idleShutdownSeconds > 0 else { return }
        cancelIdleTimer()
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + idleShutdownSeconds)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            DiagnosticsLog.write("warm-asr: idle \(Int(self.idleShutdownSeconds))s → stopping")
            self.stop()
        }
        timer.resume()
        idleTimer = timer
    }

    private func cancelIdleTimer() {
        idleTimer?.cancel()
        idleTimer = nil
    }

    // MARK: - Transcription

    /// Транскрибировать WAV через тёплый сервер.
    /// Throws — вызывающий должен сделать fallback на WhisperCLITranscriber.
    func transcribe(
        audioURL: URL,
        language: String = "auto",
        prompt: String = ""
    ) throws -> String {
        guard isRunning else { throw WhisperServerError.notRunning }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw WhisperServerError.audioReadFailed(error.localizedDescription)
        }

        let boundary = "LyraVoiceBoundary\(UUID().uuidString.prefix(8))"
        var body = Data()
        let crlf = "\r\n"

        func s(_ str: String) { body.append(str.data(using: .utf8)!) }
        func field(_ name: String, _ value: String) {
            s("--\(boundary)\(crlf)Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)\(value)\(crlf)")
        }

        s("--\(boundary)\(crlf)")
        s("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\(crlf)")
        s("Content-Type: audio/wav\(crlf)\(crlf)")
        body.append(audioData)
        s(crlf)
        field("language", language)
        if !prompt.isEmpty { field("prompt", prompt) }
        field("response_format", "json")
        s("--\(boundary)--\(crlf)")

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/inference")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30

        // Синхронный вызов через семафор — pipeline в AppDelegate уже на фоновой очереди.
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<String>()

        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            if let error {
                box.error = WhisperServerError.requestFailed(error.localizedDescription)
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                box.error = WhisperServerError.invalidResponse
                return
            }
            box.value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.resume()

        semaphore.wait()

        if let error = box.error { throw error }
        rescheduleIdleTimer()
        return box.value ?? ""
    }

    // MARK: - Private

    private func waitUntilReady(timeoutSeconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if healthCheck() { return true }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return false
    }

    private func healthCheck() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<Bool>()
        URLSession.shared.dataTask(with: request) { _, response, _ in
            box.value = (response as? HTTPURLResponse).map { $0.statusCode < 500 } ?? false
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return box.value ?? false
    }
}

// MARK: - Helpers

private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
    var error: Error?
}

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}

// MARK: - Errors

enum WhisperServerError: Error, LocalizedError {
    case notRunning
    case audioReadFailed(String)
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notRunning:             return "whisper-server не запущен"
        case .audioReadFailed(let m): return "Ошибка чтения аудио: \(m)"
        case .requestFailed(let m):   return "HTTP: \(m)"
        case .invalidResponse:        return "Неожиданный ответ сервера"
        }
    }
}
