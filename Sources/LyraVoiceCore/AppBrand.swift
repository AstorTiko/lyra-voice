import Foundation

public enum AppBrand {
    /// Отображаемое имя продукта — всегда раздельно: «Lyra Voice».
    public static let displayName = "Lyra Voice"
    public static let menuBarTitle = "LV"
    public static let executableName = "LyraVoice"
    public static let bundleIdentifier = "local.lyravoice.app"
    public static let appIconFileName = "LyraVoice.icns"
    public static let logoImageFileName = "LyraVoiceMark.png"

    /// Каталог в Application Support, где живут модели, settings.json и история.
    public static let applicationSupportDirectoryName = "LyraVoice"

    /// Версия приложения для отображения в настройках (H1). Пока без bundle Info.plist
    /// (SwiftPM exe) — фиксированное значение, обновляется вручную при релизах.
    public static let versionString = "0.1.0"

    /// Репозиторий GitHub (owner/name) для проверки обновлений через Releases API.
    /// TODO: заменить на реальный репозиторий после публикации проекта на GitHub.
    public static let updateRepository = "TODO-owner/lyra-voice"
}
