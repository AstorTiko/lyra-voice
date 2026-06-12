import AppKit
import CoreAudio
import LyraVoiceCore

/// Управляет воспроизводимым медиа на время диктовки, чтобы микрофон не ловил
/// музыку/видео и не мешал распознаванию.
///
/// - `pause`  — ставит на паузу Apple Music и Spotify через AppleScript
///   (надёжно и обратимо: возобновляем ровно то, что сами поставили на паузу).
/// - `duck`   — приглушает СИСТЕМНУЮ громкость вывода через CoreAudio.
///   ВАЖНО: раньше тут был AppleScript `set volume`, но под Hardened Runtime
///   macOS отключает scripting additions (StandardAdditions), и команда молча
///   не срабатывала. CoreAudio работает всегда, без доп. прав и глушит вообще
///   весь звук (включая YouTube в браузере).
@MainActor
final class MediaController {

    private struct Player {
        let bundleID: String
        let appName: String  // имя для AppleScript `tell application "<name>"`
    }

    private let players: [Player] = [
        Player(bundleID: "com.apple.Music", appName: "Music"),
        Player(bundleID: "com.spotify.client", appName: "Spotify")
    ]

    /// Плееры, которые мы сами поставили на паузу — их и возобновим.
    private var pausedPlayers: [Player] = []
    /// Сохранённая громкость до приглушения (0.0…1.0).
    private var restoredOutputVolume: Float?
    /// Целевой уровень приглушения.
    private let duckedVolume: Float = 0.12

    func apply(_ mode: MediaInterruptionMode) {
        DiagnosticsLog.write("media apply mode=\(mode.rawValue)")
        switch mode {
        case .none:
            break
        case .pause:
            // Music/Spotify — честная пауза с точным возобновлением. Остальные источники
            // (браузер/YouTube, системные звуки) AppleScript не видит — дополнительно
            // приглушаем системный вывод через CoreAudio, без доп. разрешений.
            pauseIfPlaying()
            duckSystemOutput()
        case .duck:
            duckSystemOutput()
        }
    }

    func restoreIfNeeded() {
        restoreSystemOutputIfNeeded()
        resumePausedIfNeeded()
    }

    // MARK: - Pause (Apple Music / Spotify)

    private func pauseIfPlaying() {
        pausedPlayers.removeAll()
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))

        for player in players where runningBundleIDs.contains(player.bundleID) {
            let state = playerState(player)
            DiagnosticsLog.write("media pause check player=\(player.appName) state=\(state ?? "nil")")
            guard state == "playing" else { continue }
            if runScript("tell application \"\(player.appName)\" to pause") != nil {
                pausedPlayers.append(player)
                DiagnosticsLog.write("media paused player=\(player.appName)")
            }
        }
    }

    private func resumePausedIfNeeded() {
        guard !pausedPlayers.isEmpty else { return }
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for player in pausedPlayers where runningBundleIDs.contains(player.bundleID) {
            runScript("tell application \"\(player.appName)\" to play")
            DiagnosticsLog.write("media resumed player=\(player.appName)")
        }
        pausedPlayers.removeAll()
    }

    /// Возвращает "playing" / "paused" / "stopped" или nil, если не удалось.
    private func playerState(_ player: Player) -> String? {
        runScript("tell application \"\(player.appName)\" to return player state as text")?
            .lowercased()
    }

    @discardableResult
    private func runScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "unknown"
            DiagnosticsLog.write("media applescript error code=\(code) message=\(message)")
            return nil
        }
        return result.stringValue
    }

    // MARK: - Duck (системная громкость через CoreAudio)

    private func duckSystemOutput() {
        guard restoredOutputVolume == nil else { return }
        guard let current = SystemVolume.outputVolume() else {
            DiagnosticsLog.write("media duck skipped: no readable output device volume")
            return
        }
        restoredOutputVolume = current
        let target = min(current, duckedVolume)
        let ok = SystemVolume.setOutputVolume(target)
        DiagnosticsLog.write("media duck from=\(String(format: "%.2f", current)) to=\(String(format: "%.2f", target)) ok=\(ok)")
    }

    private func restoreSystemOutputIfNeeded() {
        guard let volume = restoredOutputVolume else { return }
        restoredOutputVolume = nil
        let ok = SystemVolume.setOutputVolume(volume)
        DiagnosticsLog.write("media duck restore to=\(String(format: "%.2f", volume)) ok=\(ok)")
    }
}

/// Чтение/запись громкости устройства вывода по умолчанию через CoreAudio.
/// Без AppleScript и без доп. прав — работает под Hardened Runtime.
private enum SystemVolume {

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    /// Элементы (каналы), у которых есть управляемая громкость: сначала master (0),
    /// затем стерео-каналы (1, 2) — на случай устройств без master-громкости.
    private static func volumeElements(for device: AudioDeviceID) -> [UInt32] {
        let candidates: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]
        return candidates.filter { element in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element)
            return AudioObjectHasProperty(device, &address)
        }
    }

    static func outputVolume() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        for element in volumeElements(for: device) {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element)
            var volume = Float(0)
            var size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr {
                return volume
            }
        }
        return nil
    }

    @discardableResult
    static func setOutputVolume(_ value: Float) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var volume = max(0, min(1, value))
        var didSet = false
        for element in volumeElements(for: device) {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element)
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            let status = AudioObjectSetPropertyData(
                device, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &volume)
            if status == noErr { didSet = true }
        }
        return didSet
    }
}
