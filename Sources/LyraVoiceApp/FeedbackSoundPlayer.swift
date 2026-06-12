import AppKit

@MainActor
final class FeedbackSoundPlayer {
    /// Глобальный тумблер звуков диктовки (настройка «Звук уведомления»).
    var isEnabled = true

    func playRecordingStarted() {
        play(named: "Tink")
    }

    func playRecordingStopped() {
        play(named: "Pop")
    }

    func playRecordingCancelled() {
        play(named: "Purr")
    }

    private func play(named name: String) {
        guard isEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
