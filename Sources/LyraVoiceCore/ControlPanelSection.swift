import Foundation

/// Information architecture for the main Lyra Voice control panel.
///
/// Kept in Core so the AppKit sidebar order is covered by smoke tests.
public enum ControlPanelSection: String, CaseIterable, Codable, Sendable {
    case home
    case modes
    case vocabulary
    case models
    case sound
    case system
    case history

    public var title: String {
        switch self {
        case .home:
            return L.t("Главная", "Home")
        case .modes:
            return L.t("Горячие клавиши", "Hotkeys")
        case .vocabulary:
            return L.t("Словарь", "Vocabulary")
        case .models:
            return L.t("Модели", "Models")
        case .sound:
            return L.t("Звук", "Sound")
        case .system:
            return L.t("Система", "System")
        case .history:
            return L.t("История", "History")
        }
    }

    public var subtitle: String {
        switch self {
        case .home:
            return L.t("Дашборд и быстрый старт записи", "Dashboard and quick recording")
        case .modes:
            return L.t("Старт/стоп и push-to-talk", "Start/stop and push-to-talk")
        case .vocabulary:
            return L.t("Словарь замен и будущие snippets", "Replacement dictionary and future snippets")
        case .models:
            return L.t("Распознавание, точность и полировка текста", "Recognition, accuracy and text polish")
        case .sound:
            return L.t("Микрофон, медиа и звуковые сигналы", "Microphone, media and sound cues")
        case .system:
            return L.t("Автовставка, интерфейс, оверлей, Dock и разрешения", "Auto-paste, interface, overlay, Dock and permissions")
        case .history:
            return L.t("Последние диктовки и действия с текстом", "Recent dictations and text actions")
        }
    }

    public var icon: String {
        switch self {
        case .home:
            return "house.fill"
        case .modes:
            return "keyboard"
        case .vocabulary:
            return "text.book.closed"
        case .models:
            return "cpu"
        case .sound:
            return "waveform"
        case .system:
            return "gearshape"
        case .history:
            return "clock.arrow.circlepath"
        }
    }
}
