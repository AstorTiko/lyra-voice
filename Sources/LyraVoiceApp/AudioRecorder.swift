import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

struct RecordedAudio: Sendable {
    let url: URL
    let durationSeconds: TimeInterval
    let backendName: String
    /// Средний уровень записи в dBFS (RMS по всем сэмплам). nil — если бэкенд не считает
    /// уровень (fallback). Оставлен для диагностики/совместимости.
    let speechLevelDBFS: Double?
    /// ПИКОВЫЙ уровень речи в dBFS — максимум оконного RMS за запись. Это надёжный
    /// признак «была ли вообще речь»: речь всегда даёт высокие пики, даже если средний
    /// RMS низкий (паузы, тихая речь, далёкий микрофон). Именно по нему работает
    /// silence-гейт, чтобы не терять реально надиктованный текст. nil — fallback-бэкенд.
    let peakSpeechLevelDBFS: Double?
}

/// Запись микрофона через `AVAudioEngine` с возможностью выбрать устройство ввода.
/// Поток с тапа (real-time audio thread) пишет в файл и считает уровень через
/// nonisolated-состояние под локом; main только запускает/останавливает движок.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private enum Backend {
        case engine
        case fallback(AVAudioRecorder)
    }

    private var backend: Backend?
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var recordingURL: URL?
    private var startedAt: Date?
    private var stoppedDuration: TimeInterval = 0
    private var tapInstalled = false

    private let levelLock = NSLock()
    private var level: Double = 0
    /// Накопление RMS по всей записи (под levelLock) — для диагностики среднего уровня.
    private var sumSquares: Double = 0
    private var sampleFrames: Int = 0
    /// Пиковый оконный уровень в dBFS (под levelLock) — основа silence-гейта.
    private var peakDB: Double = -160
    /// PCM float-буфер конвертированных сэмплов (16 кГц, моно) — для growing-window стриминга.
    private var streamingFloatBuffer: [Float] = []

    var isRecording: Bool {
        switch backend {
        case .engine:
            return engine.isRunning
        case let .fallback(recorder):
            return recorder.isRecording
        case nil:
            return false
        }
    }

    var activeBackendName: String {
        switch backend {
        case .engine:
            return "AVAudioEngine"
        case .fallback:
            return "AVAudioRecorder"
        case nil:
            return "none"
        }
    }

    var currentDuration: TimeInterval {
        guard let startedAt else { return stoppedDuration }
        return Date().timeIntervalSince(startedAt)
    }

    var normalizedPowerLevel: Double {
        if case let .fallback(recorder) = backend {
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            return Double(max(0, min(1, (power + 55) / 55)))
        }
        levelLock.lock(); defer { levelLock.unlock() }
        return level
    }

    /// Запускает запись. `deviceUID` — UID выбранного микрофона, `nil` = системный по умолчанию.
    func start(deviceUID: String?) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyraVoice", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("recording-\(UUID().uuidString).wav")

        do {
            try startEngineRecording(url: url, deviceUID: deviceUID)
        } catch {
            DiagnosticsLog.write("recording engine failed; trying fallback error=\(error.localizedDescription)")
            cleanupEngine()
            return try startFallbackRecording(url: url, underlyingError: error)
        }
        return url
    }

    private func startEngineRecording(url: URL, deviceUID: String?) throws {
        let input = engine.inputNode
        // Маршрутизация на конкретное устройство (если задано и резолвится).
        if let deviceUID, !deviceUID.isEmpty,
           let deviceID = AudioInputDevices.deviceID(forUID: deviceUID),
           let unit = input.audioUnit {
            var id = deviceID
            let status = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else {
                throw AudioRecorderError.deviceSelectionFailed(status)
            }
        }

        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw AudioRecorderError.invalidInputFormat }

        // Целевой WAV: 16 кГц, моно, PCM16 — формат, который ждёт whisper.cpp.
        let outSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: outSettings)
        let writeFormat = file.processingFormat
        guard let converter = AVAudioConverter(from: inputFormat, to: writeFormat) else {
            throw AudioRecorderError.converterUnavailable(inputFormat.description, writeFormat.description)
        }

        self.file = file
        self.converter = converter
        self.recordingURL = url
        streamingFloatBuffer = []
        streamingFloatBuffer.reserveCapacity(16_000 * 180)  // 3 минуты
        levelLock.lock(); sumSquares = 0; sampleFrames = 0; peakDB = -160; levelLock.unlock()
        setLevel(0)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, inputFormat: inputFormat, writeFormat: writeFormat)
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            cleanupEngine()
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }
        backend = .engine
        startedAt = Date()
    }

    private func startFallbackRecording(url: URL, underlyingError: Error) throws -> URL {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                throw AudioRecorderError.engineAndFallbackFailed(
                    engine: underlyingError.localizedDescription,
                    fallback: "AVAudioRecorder.record() returned false"
                )
            }
            recordingURL = url
            backend = .fallback(recorder)
            startedAt = Date()
            setLevel(0)
            DiagnosticsLog.write("recording fallback started url=\(url.path)")
            return url
        } catch let recorderError as AudioRecorderError {
            throw recorderError
        } catch {
            throw AudioRecorderError.engineAndFallbackFailed(
                engine: underlyingError.localizedDescription,
                fallback: error.localizedDescription
            )
        }
    }

    func stop() throws -> RecordedAudio {
        guard let recordingURL else { throw AudioRecorderError.notRecording }
        let duration = currentDuration
        let backendName = activeBackendName
        switch backend {
        case .engine:
            cleanupEngine()
        case let .fallback(recorder):
            recorder.stop()
        case nil:
            break
        }
        self.file = nil
        self.converter = nil
        self.recordingURL = nil
        self.startedAt = nil
        self.stoppedDuration = duration
        self.backend = nil
        let speechLevelDBFS: Double?
        let peakSpeechLevelDBFS: Double?
        levelLock.lock()
        streamingFloatBuffer = []
        if sampleFrames > 0 {
            let rms = (sumSquares / Double(sampleFrames)).squareRoot()
            speechLevelDBFS = 20 * log10(max(rms, 1e-7))
            peakSpeechLevelDBFS = peakDB
        } else {
            speechLevelDBFS = nil
            peakSpeechLevelDBFS = nil
        }
        levelLock.unlock()
        return RecordedAudio(
            url: recordingURL,
            durationSeconds: duration,
            backendName: backendName,
            speechLevelDBFS: speechLevelDBFS,
            peakSpeechLevelDBFS: peakSpeechLevelDBFS
        )
    }

    func cancel() throws {
        let recorded = try stop()
        try? FileManager.default.removeItem(at: recorded.url)
    }

    // MARK: - Audio thread

    private func process(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, writeFormat: AVAudioFormat) {
        guard let converter, let file else { return }
        let ratio = writeFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: writeFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, statusPtr in
            if fed {
                statusPtr.pointee = .noDataNow
                return nil
            }
            fed = true
            statusPtr.pointee = .haveData
            return buffer
        }
        if status == .haveData, outBuffer.frameLength > 0 {
            try? file.write(from: outBuffer)
            appendToStreamingBuffer(outBuffer)
        }
        updateLevel(from: buffer)
    }

    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0
        for i in 0..<frames {
            let sample = channel[i]
            sum += sample * sample
        }
        let rms = (sum / Float(frames)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        levelLock.lock()
        sumSquares += Double(sum); sampleFrames += frames
        if Double(db) > peakDB { peakDB = Double(db) }   // пик оконного уровня за запись
        levelLock.unlock()
        setLevel(Double(max(0, min(1, (db + 55) / 55))))
    }

    private func setLevel(_ value: Double) {
        levelLock.lock(); level = value; levelLock.unlock()
    }

    private func appendToStreamingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        // Копируем до локвания, чтобы удерживать лок минимально долго.
        let slice = Array(UnsafeBufferPointer(start: floatData, count: count))
        levelLock.lock()
        streamingFloatBuffer.append(contentsOf: slice)
        levelLock.unlock()
    }

    /// Снимок текущего буфера записи как WAV-файл. Используется для growing-window ASR.
    /// Возвращает nil, если запись не идёт или буфер пуст.
    func currentSnapshot() -> URL? {
        guard isRecording else { return nil }
        levelLock.lock()
        let samples = streamingFloatBuffer
        levelLock.unlock()
        guard !samples.isEmpty else { return nil }
        return writeWAVSnapshot(samples: samples, sampleRate: 16_000)
    }

    private func writeWAVSnapshot(samples: [Float], sampleRate: Int) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LyraVoiceStreaming")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("snap-\(UUID().uuidString.prefix(6)).wav")

        let int16Samples = samples.map { s -> Int16 in
            Int16(max(-32767, min(32767, s * 32767.0)))
        }
        let sr = UInt32(sampleRate)
        let dataSize = UInt32(int16Samples.count * 2)

        func le<T: FixedWidthInteger>(_ v: T) -> Data {
            withUnsafeBytes(of: v.littleEndian) { Data($0) }
        }

        var header = Data()
        header += "RIFF".data(using: .ascii)!;  header += le(36 + dataSize)
        header += "WAVE".data(using: .ascii)!
        header += "fmt ".data(using: .ascii)!;  header += le(UInt32(16))
        header += le(UInt16(1))                   // PCM
        header += le(UInt16(1))                   // mono
        header += le(sr)
        header += le(sr * 2)                      // byteRate
        header += le(UInt16(2))                   // blockAlign
        header += le(UInt16(16))                  // bitsPerSample
        header += "data".data(using: .ascii)!;  header += le(dataSize)

        var fileData = header
        int16Samples.withUnsafeBytes { fileData.append(Data($0)) }

        guard (try? fileData.write(to: url)) != nil else { return nil }
        return url
    }

    private func cleanupEngine() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
    }
}

enum AudioRecorderError: LocalizedError {
    case invalidInputFormat
    case converterUnavailable(String, String)
    case deviceSelectionFailed(OSStatus)
    case engineStartFailed(String)
    case engineAndFallbackFailed(engine: String, fallback: String)
    case notRecording

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat:
            return "Could not start microphone recording: input format is unavailable."
        case let .converterUnavailable(input, output):
            return "Could not start microphone recording: cannot convert \(input) to \(output)."
        case let .deviceSelectionFailed(status):
            return "Could not select microphone device (CoreAudio status \(status))."
        case let .engineStartFailed(message):
            return "Could not start microphone recording: \(message)"
        case let .engineAndFallbackFailed(engine, fallback):
            return "Could not start microphone recording. Engine: \(engine). Fallback: \(fallback)"
        case .notRecording:
            return "No active recording."
        }
    }
}
