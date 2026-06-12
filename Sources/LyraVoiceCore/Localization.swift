import Foundation

/// Язык интерфейса приложения.
public enum AppLanguage: String, CaseIterable {
    case ru
    case en

    public var displayName: String {
        switch self {
        case .ru:
            return "Русский"
        case .en:
            return "English"
        }
    }
}

/// Лёгкая локализация инлайн-парами: `L.t("Русский", "English")`. Без отдельного
/// файла ключей — строка и её перевод живут рядом. Текущий язык — глобальный,
/// меняется из настроек; панель пересобирается при переключении. Читается/пишется
/// только на главном потоке (UI), поэтому `nonisolated(unsafe)` безопасен.
///
/// Живёт в Core, чтобы и App-слой, и доменные типы (`ControlPanelState`,
/// `ModelProfile`) показывали текст на выбранном языке из одного источника.
public enum L {
    nonisolated(unsafe) public static var current: AppLanguage = .ru

    public static func set(_ code: String) {
        current = AppLanguage(rawValue: code.lowercased()) ?? .en
    }

    /// Возвращает строку на текущем языке интерфейса.
    public static func t(_ ru: String, _ en: String) -> String {
        current == .en ? en : ru
    }

    /// Человекочитаемое имя языка интерфейса.
    public static func languageName(_ code: String) -> String {
        let normalized = code.lowercased()
        if normalized == AppSettings.automaticInterfaceLanguage {
            return t("Авто (по системе)", "Auto (System)")
        }
        return AppLanguage(rawValue: normalized)?.displayName ?? AppLanguage.en.displayName
    }
}
