import Foundation

/// Growing-window chunked ASR: каждые `intervalSeconds` снимает буфер записи
/// и транскрибирует его через тёплый whisper-server. Результат всегда содержит
/// текст С НАЧАЛА записи (growing window — лучшая точность, модель видит контекст).
/// Запускается только если whisper-server активен; при его отсутствии start() — no-op.
final class StreamingASRService: @unchecked Sendable {
    static let shared = StreamingASRService()
    private init() {}

    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var _currentText: String = ""
    private let queue = DispatchQueue(label: "ai.lyra.streaming-asr", qos: .userInitiated)

    var intervalSeconds: Double = 1.5

    /// Вызывается на main queue при каждом обновлении текста.
    var onTextUpdate: (@Sendable @MainActor (String) -> Void)?

    var currentText: String { lock.withLock { _currentText } }
    var isActive: Bool { lock.withLock { timer != nil } }

    @discardableResult
    func start(recorder: AudioRecorder, language: String, prompt: String) -> Bool {
        stop()
        lock.withLock { _currentText = "" }

        // Сервер мог ещё подниматься (его будят при старте записи) — НЕ выходим сразу,
        // а проверяем готовность на каждом тике: стриминг подхватится, как только сервер готов.
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds, leeway: .milliseconds(300))
        t.setEventHandler { [weak self, weak recorder] in
            guard let self, let recorder else { return }
            guard WhisperServerService.shared.isRunning else { return }
            guard let snapshot = recorder.currentSnapshot() else { return }
            defer { try? FileManager.default.removeItem(at: snapshot) }
            do {
                let text = try WhisperServerService.shared.transcribe(
                    audioURL: snapshot, language: language, prompt: prompt
                )
                guard !text.isEmpty else { return }
                self.lock.withLock { self._currentText = text }
                let cb = self.onTextUpdate
                DispatchQueue.main.async { Task { @MainActor in cb?(text) } }
            } catch {
                DiagnosticsLog.write("streaming-asr: chunk failed \(error.localizedDescription)")
            }
        }
        t.resume()
        lock.withLock { timer = t }
        DiagnosticsLog.write("streaming-asr: started interval=\(intervalSeconds)s")
        return true
    }

    /// Останавливает таймер. Возвращает последний накопленный текст.
    @discardableResult
    func stop() -> String {
        let t: DispatchSourceTimer? = lock.withLock { let t = timer; timer = nil; return t }
        t?.cancel()
        let text = lock.withLock { _currentText }
        if !text.isEmpty { DiagnosticsLog.write("streaming-asr: stopped lastText=\(text.prefix(60))") }
        return text
    }
}

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
