import Foundation

public struct OverlaySize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum OverlayMetrics {
    /// Push-to-talk: минимальная капсула — только живая аудиоволна, без кнопок
    /// (отпустил клавишу = завершить, кнопки не нужны).
    public static let pushToTalkSize = OverlaySize(width: 66, height: 26)
    /// Toggle (hands-free): капсула с кнопками ✕ отмена / ✓ подтвердить вокруг волны.
    public static let toggleSize = OverlaySize(width: 100, height: 26)
    /// Стриминг-панель: расширенная капсула с живым текстом транскрипции (3 строки + воздух).
    public static let streamingSize = OverlaySize(width: 300, height: 104)

    /// Совместимость со старым кодом (по умолчанию — toggle-размер).
    public static let size = toggleSize

    /// Полное скругление (капсула) — равно половине высоты.
    public static let cornerRadius = 13.0
    public static let buttonSize = 20.0
    public static let bottomOffset = 28.0
}
