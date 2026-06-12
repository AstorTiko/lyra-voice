import Foundation

public enum HotkeyMode: String, Codable, Equatable, Sendable {
    case toggle
    case pushToTalk
}

public enum DictationHotkeyAction: String, Codable, Equatable, Sendable {
    case toggleRecording
    case pushToTalk
}

public struct Hotkey: Codable, Equatable, Sendable {
    public static let functionKeyCode = UInt16.max

    public var keyCode: UInt16
    public var modifierFlags: [String]

    public init(keyCode: UInt16, modifierFlags: [String]) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    public var displayText: String {
        if keyCode == Self.functionKeyCode, modifierFlags == ["function"] {
            return "Fn"
        }

        let modifierText = modifierFlags.map { flag in
            switch flag {
            case "command":
                return "⌘"
            case "shift":
                return "⇧"
            case "option":
                return "⌥"
            case "control":
                return "⌃"
            case "function":
                return "Fn"
            default:
                return flag.capitalized
            }
        }

        return (modifierText + [Self.keyName(for: keyCode)]).joined(separator: " ")
    }

    public var isAssignable: Bool {
        if keyCode == Self.functionKeyCode {
            return modifierFlags == ["function"]
        }
        return !modifierFlags.isEmpty && !Self.isModifierOnlyKeyCode(keyCode)
    }

    public static var fn: Hotkey {
        Hotkey(keyCode: functionKeyCode, modifierFlags: ["function"])
    }

    public static func isModifierOnlyKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 56, 58, 59, 60, 61, 62:
            return true
        default:
            return false
        }
    }

    public static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 54, 55:
            return "Command"
        case 56, 60:
            return "Shift"
        case 58, 61:
            return "Option"
        case 59, 62:
            return "Control"
        case 36, 76:
            return "Return"
        case 49:
            return "Space"
        case 53:
            return "Escape"
        case 48:
            return "Tab"
        case 51:
            return "Delete"
        case 117:
            return "Forward Delete"
        case 123:
            return "←"
        case 124:
            return "→"
        case 125:
            return "↓"
        case 126:
            return "↑"
        case 18:
            return "1"
        case 19:
            return "2"
        case 20:
            return "3"
        case 21:
            return "4"
        case 23:
            return "5"
        case 22:
            return "6"
        case 26:
            return "7"
        case 28:
            return "8"
        case 25:
            return "9"
        case 29:
            return "0"
        case 27:
            return "-"
        case 24:
            return "="
        case 33:
            return "["
        case 30:
            return "]"
        case 42:
            return "\\"
        case 41:
            return ";"
        case 39:
            return "'"
        case 43:
            return ","
        case 47:
            return "."
        case 44:
            return "/"
        case 50:
            return "`"
        case 0:
            return "A"
        case 1:
            return "S"
        case 2:
            return "D"
        case 3:
            return "F"
        case 4:
            return "H"
        case 5:
            return "G"
        case 6:
            return "Z"
        case 7:
            return "X"
        case 8:
            return "C"
        case 9:
            return "V"
        case 11:
            return "B"
        case 12:
            return "Q"
        case 13:
            return "W"
        case 14:
            return "E"
        case 15:
            return "R"
        case 16:
            return "Y"
        case 17:
            return "T"
        case 31:
            return "O"
        case 32:
            return "U"
        case 34:
            return "I"
        case 35:
            return "P"
        case 37:
            return "L"
        case 38:
            return "J"
        case 40:
            return "K"
        case 45:
            return "N"
        case 46:
            return "M"
        case functionKeyCode:
            return "Fn"
        default:
            return "Key \(keyCode)"
        }
    }
}

/// Запись пользовательского словаря замен: «джипити» → «GPT».
public struct DictionaryEntry: Codable, Equatable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// Уровень полировки текста после распознавания.
public enum PolishLevel: String, Codable, Equatable, Sendable {
    /// Только правила (мгновенно, офлайн, бесплатно).
    case rules
    /// Локальная LLM (MLX) — режим «Красиво», офлайн.
    case localLLM
    /// Облачная LLM — по API-ключу.
    case cloud
}

public enum MediaInterruptionMode: String, Codable, Equatable, Sendable {
    case none
    case pause
    case duck
}

/// Способ вставки текста после диктовки.
public enum PasteMode: String, Codable, Equatable, Sendable {
    /// Скопировать в буфер обмена → Cmd+V (стандарт, работает в большинстве приложений).
    case clipboard
    /// Симулировать нажатия клавиш (для терминалов и полей, не принимающих вставку).
    case simulateTyping
}

/// Режим отображения оверлея записи.
public enum OverlayDisplayMode: String, Codable, Equatable, Sendable, CaseIterable {
    /// Оверлей скрыт во время записи и транскрибации.
    case none = "none"
    /// Компактный pill с аудиоволной, без живого текста.
    case pill = "pill"
    /// Расширенная панель с живым текстом транскрипции (по умолчанию).
    case streaming = "streaming"

    public var displayName: String {
        switch self {
        case .none: return L.t("Нет", "None")
        case .pill: return L.t("Компактный", "Compact")
        case .streaming: return L.t("Текст в реальном времени", "Live text")
        }
    }
}

/// Сколько хранить локальные записи (`Recordings/`) перед автоудалением.
/// `forever` — автоудаление выключено.
public enum RecordingsRetentionPeriod: String, Codable, Equatable, Sendable, CaseIterable {
    case forever
    case oneDay
    case oneWeek
    case twoWeeks
    case oneMonth
    case sixMonths
    case oneYear

    public var displayName: String {
        switch self {
        case .forever: return L.t("Всегда", "Forever")
        case .oneDay: return L.t("1 день", "One day")
        case .oneWeek: return L.t("1 неделя", "One week")
        case .twoWeeks: return L.t("2 недели", "Two weeks")
        case .oneMonth: return L.t("1 месяц", "One month")
        case .sixMonths: return L.t("6 месяцев", "Six months")
        case .oneYear: return L.t("1 год", "One year")
        }
    }

    /// Возраст записи, после которого она удаляется. `nil` — не удалять.
    public var days: Int? {
        switch self {
        case .forever: return nil
        case .oneDay: return 1
        case .oneWeek: return 7
        case .twoWeeks: return 14
        case .oneMonth: return 30
        case .sixMonths: return 182
        case .oneYear: return 365
        }
    }
}

/// Провайдер транскрибации.
public enum TranscriptionProvider: String, Codable, Equatable, Sendable {
    /// Локальный whisper.cpp (приватно, офлайн).
    case local
    /// OpenAI Whisper API (требует ключ, аудио уходит на сервер).
    case openAI
}

/// Модель облачной транскрибации OpenAI.
public enum OpenAITranscriptionModel: String, Codable, Equatable, Sendable, CaseIterable {
    case whisper1 = "whisper-1"
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"

    public var displayName: String {
        switch self {
        case .whisper1: return "Whisper-1"
        case .gpt4oTranscribe: return "GPT-4o Transcribe"
        case .gpt4oMiniTranscribe: return "GPT-4o Mini Transcribe"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var selectedModelID: String
    public var language: String
    public var initialPrompt: String
    public var toggleHotkey: Hotkey
    public var pushToTalkHotkey: Hotkey
    public var whisperBinaryPath: String
    public var modelDirectoryPath: String
    /// Что делать с воспроизводимым медиа на время записи.
    public var mediaInterruptionMode: MediaInterruptionMode
    /// Уровень полировки текста.
    public var polishLevel: PolishLevel
    /// Читать локальный контекст в момент диктовки: focused Accessibility element
    /// и короткую подсказку из буфера обмена. По умолчанию выключено.
    public var smartContextEnabled: Bool
    /// Пользовательский словарь замен.
    public var dictionaryReplacements: [DictionaryEntry]
    /// Автоматически вставлять текст (иначе — только копировать в буфер обмена).
    public var autoPasteEnabled: Bool
    /// Убирать слова-паразиты при полировке (эээ, ну, как бы…).
    public var removeFillerWords: Bool
    /// UID выбранного микрофона (пусто = системный по умолчанию).
    public var inputDeviceUID: String
    /// Режим языка интерфейса приложения: "auto" или код поддерживаемого языка.
    public var interfaceLanguage: String
    /// Путь к бинарю `llama-server` (llama.cpp) для локальной LLM-полировки.
    public var localLLMServerBinaryPath: String
    /// Пройден ли первичный онбординг (права, знакомство с хоткеем).
    public var hasCompletedOnboarding: Bool
    /// Запускать приложение при входе в систему (login item, `SMAppService`).
    public var launchAtLogin: Bool
    /// Показывать иконку в Dock (иначе — только в строке меню, как агент).
    public var showInDock: Bool
    /// Проигрывать звуки старта/стопа/отмены записи.
    public var playFeedbackSounds: Bool
    /// Сохранять записанный звук + распознанный текст в локальный корпус
    /// (`Recordings/`) для настройки качества распознавания. По умолчанию
    /// ВЫКЛЮЧЕНО ради приватности — включается пользователем явно.
    public var saveRecordings: Bool
    /// Включить VAD (Voice Activity Detection) — отсекает тишину/паузы,
    /// предотвращает галлюцинации и повторы при долгих паузах.
    public var vadEnabled: Bool
    /// Предобработка аудио через ffmpeg (мягкий trim тишины по краям + loudnorm)
    /// перед передачей в Whisper. По умолчанию ВЫКЛЮЧЕНО: запись уже в 16 кГц/моно,
    /// Whisper нормализует сам, а обработка чаще вредит распознаванию, чем помогает.
    /// Включается вручную для тихих/шумных микрофонов.
    public var audioNormalizationEnabled: Bool
    /// Нажимать Enter после вставки — удобно для чатов и мессенджеров.
    public var autoEnterAfterPaste: Bool
    /// Режим вставки текста: clipboard (Cmd+V) или simulateTyping (посимвольный ввод).
    public var pasteMode: PasteMode
    /// Провайдер транскрибации: local (whisper.cpp) или openAI (API).
    public var transcriptionProvider: TranscriptionProvider
    /// API-ключ OpenAI (хранится в settings.json; для производственного использования → Keychain).
    public var openAIAPIKey: String
    /// Модель облачной транскрибации OpenAI.
    public var openAITranscriptionModel: OpenAITranscriptionModel
    /// Режим оверлея записи: none (скрыт), pill (компактный), streaming (живой текст).
    public var overlayDisplayMode: OverlayDisplayMode
    /// Языки, на которых говорит пользователь (whisper-коды, по порядку приоритета — первый
    /// основной). Используются, когда автоопределение выключено. Whisper принимает один язык
    /// на распознавание, поэтому при выключенном авто форсим первый из списка.
    public var spokenLanguages: [String]
    /// Автоматически определять язык речи (whisper `auto`). Если выключено — форсим
    /// основной язык из `spokenLanguages` (точнее для одноязычной речи).
    public var autoDetectLanguage: Bool
    /// Автоматически проверять наличие новых версий приложения (H1).
    public var automaticallyCheckForUpdates: Bool
    /// Писать диагностический лог (`diagnostics.log`) при ошибках.
    public var diagnosticsLoggingEnabled: Bool
    /// Через какое время автоматически удалять локальные записи из `Recordings/`
    /// (только когда `saveRecordings` включён). `forever` — не удалять.
    public var recordingsRetention: RecordingsRetentionPeriod

    public init(
        selectedModelID: String,
        language: String,
        initialPrompt: String,
        toggleHotkey: Hotkey,
        pushToTalkHotkey: Hotkey,
        whisperBinaryPath: String,
        modelDirectoryPath: String,
        mediaInterruptionMode: MediaInterruptionMode = .pause,
        polishLevel: PolishLevel = .rules,
        smartContextEnabled: Bool = false,
        dictionaryReplacements: [DictionaryEntry] = [],
        autoPasteEnabled: Bool = true,
        removeFillerWords: Bool = true,
        inputDeviceUID: String = "",
        interfaceLanguage: String = AppSettings.automaticInterfaceLanguage,
        localLLMServerBinaryPath: String = "/opt/homebrew/bin/llama-server",
        hasCompletedOnboarding: Bool = false,
        launchAtLogin: Bool = false,
        showInDock: Bool = true,
        playFeedbackSounds: Bool = true,
        saveRecordings: Bool = false,
        vadEnabled: Bool = true,
        audioNormalizationEnabled: Bool = false,
        autoEnterAfterPaste: Bool = false,
        pasteMode: PasteMode = .clipboard,
        transcriptionProvider: TranscriptionProvider = .local,
        openAIAPIKey: String = "",
        openAITranscriptionModel: OpenAITranscriptionModel = .gpt4oTranscribe,
        overlayDisplayMode: OverlayDisplayMode = .streaming,
        spokenLanguages: [String] = [],
        autoDetectLanguage: Bool = true,
        automaticallyCheckForUpdates: Bool = true,
        diagnosticsLoggingEnabled: Bool = true,
        recordingsRetention: RecordingsRetentionPeriod = .forever
    ) {
        self.selectedModelID = selectedModelID
        self.language = language
        self.initialPrompt = initialPrompt
        self.toggleHotkey = toggleHotkey
        self.pushToTalkHotkey = pushToTalkHotkey
        self.whisperBinaryPath = whisperBinaryPath
        self.modelDirectoryPath = modelDirectoryPath
        self.mediaInterruptionMode = mediaInterruptionMode
        self.polishLevel = polishLevel
        self.smartContextEnabled = smartContextEnabled
        self.dictionaryReplacements = dictionaryReplacements
        self.autoPasteEnabled = autoPasteEnabled
        self.removeFillerWords = removeFillerWords
        self.inputDeviceUID = inputDeviceUID
        self.interfaceLanguage = interfaceLanguage
        self.localLLMServerBinaryPath = localLLMServerBinaryPath
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.launchAtLogin = launchAtLogin
        self.showInDock = showInDock
        self.playFeedbackSounds = playFeedbackSounds
        self.saveRecordings = saveRecordings
        self.vadEnabled = vadEnabled
        self.audioNormalizationEnabled = audioNormalizationEnabled
        self.autoEnterAfterPaste = autoEnterAfterPaste
        self.pasteMode = pasteMode
        self.transcriptionProvider = transcriptionProvider
        self.openAIAPIKey = openAIAPIKey
        self.openAITranscriptionModel = openAITranscriptionModel
        self.overlayDisplayMode = overlayDisplayMode
        self.spokenLanguages = spokenLanguages
        self.autoDetectLanguage = autoDetectLanguage
        self.automaticallyCheckForUpdates = automaticallyCheckForUpdates
        self.diagnosticsLoggingEnabled = diagnosticsLoggingEnabled
        self.recordingsRetention = recordingsRetention
    }

    /// Язык, который реально передаём в whisper. При включённом авто — `auto`; иначе —
    /// основной (первый) выбранный язык, либо `auto`, если выбора нет.
    public var effectiveTranscriptionLanguage: String {
        if autoDetectLanguage { return "auto" }
        if let primary = spokenLanguages.first, !primary.isEmpty { return primary }
        return language.isEmpty ? "auto" : language
    }

    /// Код режима, в котором язык интерфейса следует за системными предпочтениями macOS.
    public static let automaticInterfaceLanguage = "auto"

    /// Язык интерфейса, если системный язык не входит в список поддерживаемых.
    public static let fallbackInterfaceLanguage = AppLanguage.en.rawValue

    /// Единый список реально поддерживаемых языков интерфейса. При добавлении
    /// новых переводов расширяй `AppLanguage`; picker и resolver подхватят код.
    public static var supportedInterfaceLanguages: [String] {
        AppLanguage.allCases.map(\.rawValue)
    }

    /// Язык интерфейса по умолчанию — по системным предпочтениям.
    public static var systemDefaultInterfaceLanguage: String {
        resolvedInterfaceLanguage(automaticInterfaceLanguage)
    }

    /// Превращает сохранённый режим (`auto` или явный код языка) в язык, который
    /// можно применить к `L`. `Locale.preferredLanguages` упорядочен пользователем,
    /// поэтому выбираем первый поддерживаемый код, а не только первый системный.
    public static func resolvedInterfaceLanguage(
        _ storedCode: String,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let normalized = storedCode.lowercased()
        if normalized != automaticInterfaceLanguage {
            return supportedInterfaceLanguages.contains(normalized) ? normalized : fallbackInterfaceLanguage
        }

        for preferred in preferredLanguages {
            let code = preferred
                .lowercased()
                .split { $0 == "-" || $0 == "_" }
                .first
                .map(String.init) ?? preferred.lowercased()
            if supportedInterfaceLanguages.contains(code) {
                return code
            }
        }
        return fallbackInterfaceLanguage
    }

    public var effectiveInterfaceLanguage: String {
        Self.resolvedInterfaceLanguage(interfaceLanguage)
    }

    enum CodingKeys: String, CodingKey {
        case selectedModelID
        case language
        case initialPrompt
        case toggleHotkey
        case pushToTalkHotkey
        case hotkeyMode
        case hotkey
        case whisperBinaryPath
        case modelDirectoryPath
        case mediaInterruptionMode
        case pauseMediaWhileRecording
        case polishLevel
        case smartContextEnabled
        // Legacy split context toggles, migrated into `smartContextEnabled`.
        case screenContextEnabled
        case clipboardContextEnabled
        case dictionaryReplacements
        case autoPasteEnabled
        case removeFillerWords
        case inputDeviceUID
        case interfaceLanguage
        case localLLMServerBinaryPath
        case hasCompletedOnboarding
        case launchAtLogin
        case showInDock
        case playFeedbackSounds
        case saveRecordings
        case vadEnabled
        case audioNormalizationEnabled
        case autoEnterAfterPaste
        case pasteMode
        case transcriptionProvider
        case openAIAPIKey
        case openAITranscriptionModel
        case overlayDisplayMode
        case spokenLanguages
        case autoDetectLanguage
        case automaticallyCheckForUpdates
        case diagnosticsLoggingEnabled
        case recordingsRetention
    }

    public init(from decoder: Decoder) throws {
        let defaults = AppSettings.defaultSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedModelID = try container.decodeIfPresent(String.self, forKey: .selectedModelID) ?? defaults.selectedModelID
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? defaults.language
        let decodedPrompt = try container.decodeIfPresent(String.self, forKey: .initialPrompt) ?? defaults.initialPrompt
        // Миграция: старый instruction-промпт → новый глоссарий (инструкции whisper не выполняет).
        initialPrompt = decodedPrompt == AppSettings.legacyInstructionPrompt ? defaults.initialPrompt : decodedPrompt
        let decodedToggleHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .toggleHotkey)
        let legacyHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        let toggleCandidate = decodedToggleHotkey ?? legacyHotkey ?? defaults.toggleHotkey
        toggleHotkey = toggleCandidate.isAssignable ? toggleCandidate : defaults.toggleHotkey

        let decodedPushToTalkHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .pushToTalkHotkey)
        if let decodedPushToTalkHotkey {
            pushToTalkHotkey = decodedPushToTalkHotkey.isAssignable ? decodedPushToTalkHotkey : defaults.pushToTalkHotkey
        } else {
            pushToTalkHotkey = defaults.pushToTalkHotkey == toggleHotkey
                ? AppSettings.alternatePushToTalkHotkey
                : defaults.pushToTalkHotkey
        }
        whisperBinaryPath = try container.decodeIfPresent(String.self, forKey: .whisperBinaryPath) ?? defaults.whisperBinaryPath
        modelDirectoryPath = try container.decodeIfPresent(String.self, forKey: .modelDirectoryPath) ?? defaults.modelDirectoryPath
        if let decodedMode = try container.decodeIfPresent(MediaInterruptionMode.self, forKey: .mediaInterruptionMode) {
            mediaInterruptionMode = decodedMode
        } else if let legacyPause = try container.decodeIfPresent(Bool.self, forKey: .pauseMediaWhileRecording) {
            mediaInterruptionMode = legacyPause ? .pause : .none
        } else {
            mediaInterruptionMode = defaults.mediaInterruptionMode
        }
        polishLevel = try container.decodeIfPresent(PolishLevel.self, forKey: .polishLevel) ?? defaults.polishLevel
        if let decodedSmartContext = try container.decodeIfPresent(Bool.self, forKey: .smartContextEnabled) {
            smartContextEnabled = decodedSmartContext
        } else {
            let legacyScreenContext = try container.decodeIfPresent(Bool.self, forKey: .screenContextEnabled) ?? false
            let legacyClipboardContext = try container.decodeIfPresent(Bool.self, forKey: .clipboardContextEnabled) ?? false
            smartContextEnabled = legacyScreenContext || legacyClipboardContext || defaults.smartContextEnabled
        }
        dictionaryReplacements = try container.decodeIfPresent([DictionaryEntry].self, forKey: .dictionaryReplacements) ?? defaults.dictionaryReplacements
        autoPasteEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoPasteEnabled) ?? defaults.autoPasteEnabled
        removeFillerWords = try container.decodeIfPresent(Bool.self, forKey: .removeFillerWords) ?? defaults.removeFillerWords
        inputDeviceUID = try container.decodeIfPresent(String.self, forKey: .inputDeviceUID) ?? defaults.inputDeviceUID
        interfaceLanguage = try container.decodeIfPresent(String.self, forKey: .interfaceLanguage) ?? defaults.interfaceLanguage
        localLLMServerBinaryPath = try container.decodeIfPresent(String.self, forKey: .localLLMServerBinaryPath) ?? defaults.localLLMServerBinaryPath
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? defaults.hasCompletedOnboarding
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        showInDock = try container.decodeIfPresent(Bool.self, forKey: .showInDock) ?? defaults.showInDock
        playFeedbackSounds = try container.decodeIfPresent(Bool.self, forKey: .playFeedbackSounds) ?? defaults.playFeedbackSounds
        saveRecordings = try container.decodeIfPresent(Bool.self, forKey: .saveRecordings) ?? defaults.saveRecordings
        vadEnabled = try container.decodeIfPresent(Bool.self, forKey: .vadEnabled) ?? defaults.vadEnabled
        audioNormalizationEnabled = try container.decodeIfPresent(Bool.self, forKey: .audioNormalizationEnabled) ?? defaults.audioNormalizationEnabled
        autoEnterAfterPaste = try container.decodeIfPresent(Bool.self, forKey: .autoEnterAfterPaste) ?? defaults.autoEnterAfterPaste
        pasteMode = try container.decodeIfPresent(PasteMode.self, forKey: .pasteMode) ?? defaults.pasteMode
        transcriptionProvider = try container.decodeIfPresent(TranscriptionProvider.self, forKey: .transcriptionProvider) ?? defaults.transcriptionProvider
        openAIAPIKey = try container.decodeIfPresent(String.self, forKey: .openAIAPIKey) ?? defaults.openAIAPIKey
        openAITranscriptionModel = try container.decodeIfPresent(OpenAITranscriptionModel.self, forKey: .openAITranscriptionModel) ?? defaults.openAITranscriptionModel
        overlayDisplayMode = try container.decodeIfPresent(OverlayDisplayMode.self, forKey: .overlayDisplayMode) ?? defaults.overlayDisplayMode

        // Мультиязык: если новых полей ещё нет — мигрируем из старого `language`.
        if let decodedSpoken = try container.decodeIfPresent([String].self, forKey: .spokenLanguages),
           let decodedAuto = try container.decodeIfPresent(Bool.self, forKey: .autoDetectLanguage) {
            spokenLanguages = decodedSpoken
            autoDetectLanguage = decodedAuto
        } else if language == "auto" || language.isEmpty {
            autoDetectLanguage = true
            spokenLanguages = []
        } else {
            autoDetectLanguage = false
            spokenLanguages = [language]
        }
        automaticallyCheckForUpdates = try container.decodeIfPresent(Bool.self, forKey: .automaticallyCheckForUpdates) ?? defaults.automaticallyCheckForUpdates
        diagnosticsLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagnosticsLoggingEnabled) ?? defaults.diagnosticsLoggingEnabled
        recordingsRetention = try container.decodeIfPresent(RecordingsRetentionPeriod.self, forKey: .recordingsRetention) ?? defaults.recordingsRetention
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedModelID, forKey: .selectedModelID)
        try container.encode(language, forKey: .language)
        try container.encode(initialPrompt, forKey: .initialPrompt)
        try container.encode(toggleHotkey, forKey: .toggleHotkey)
        try container.encode(pushToTalkHotkey, forKey: .pushToTalkHotkey)
        try container.encode(whisperBinaryPath, forKey: .whisperBinaryPath)
        try container.encode(modelDirectoryPath, forKey: .modelDirectoryPath)
        try container.encode(mediaInterruptionMode, forKey: .mediaInterruptionMode)
        try container.encode(polishLevel, forKey: .polishLevel)
        try container.encode(smartContextEnabled, forKey: .smartContextEnabled)
        try container.encode(dictionaryReplacements, forKey: .dictionaryReplacements)
        try container.encode(autoPasteEnabled, forKey: .autoPasteEnabled)
        try container.encode(removeFillerWords, forKey: .removeFillerWords)
        try container.encode(inputDeviceUID, forKey: .inputDeviceUID)
        try container.encode(interfaceLanguage, forKey: .interfaceLanguage)
        try container.encode(localLLMServerBinaryPath, forKey: .localLLMServerBinaryPath)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(showInDock, forKey: .showInDock)
        try container.encode(playFeedbackSounds, forKey: .playFeedbackSounds)
        try container.encode(saveRecordings, forKey: .saveRecordings)
        try container.encode(vadEnabled, forKey: .vadEnabled)
        try container.encode(audioNormalizationEnabled, forKey: .audioNormalizationEnabled)
        try container.encode(autoEnterAfterPaste, forKey: .autoEnterAfterPaste)
        try container.encode(pasteMode, forKey: .pasteMode)
        try container.encode(transcriptionProvider, forKey: .transcriptionProvider)
        try container.encode(openAIAPIKey, forKey: .openAIAPIKey)
        try container.encode(openAITranscriptionModel, forKey: .openAITranscriptionModel)
        try container.encode(overlayDisplayMode, forKey: .overlayDisplayMode)
        try container.encode(spokenLanguages, forKey: .spokenLanguages)
        try container.encode(autoDetectLanguage, forKey: .autoDetectLanguage)
        try container.encode(automaticallyCheckForUpdates, forKey: .automaticallyCheckForUpdates)
        try container.encode(diagnosticsLoggingEnabled, forKey: .diagnosticsLoggingEnabled)
        try container.encode(recordingsRetention, forKey: .recordingsRetention)
    }

    public static func defaultSettings(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> AppSettings {
        let modelDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(AppBrand.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)

        return AppSettings(
            selectedModelID: "large-v3",
            language: "auto",
            initialPrompt: AppSettings.defaultInitialPrompt,
            toggleHotkey: Hotkey(keyCode: 49, modifierFlags: ["control", "option"]),
            pushToTalkHotkey: .fn,
            whisperBinaryPath: "/opt/homebrew/bin/whisper-cli",
            modelDirectoryPath: modelDirectory.path,
            mediaInterruptionMode: .pause,
            polishLevel: .rules
        )
    }

    public static var alternatePushToTalkHotkey: Hotkey {
        Hotkey(keyCode: 40, modifierFlags: ["control", "option"])
    }

    /// Глоссарий имён собственных/терминов для whisper `initial_prompt`. ВАЖНО: whisper
    /// НЕ выполняет инструкции — `initial_prompt` работает как «предшествующий текст» и лишь
    /// смещает словарь/стиль. Поэтому здесь список терминов, а не указания. Помогает писать
    /// «Lyra Voice», «Cursor», «GPT» вместо фонетических искажений («Leroyce» и т.п.).
    public static let defaultInitialPrompt = "Lyra Voice, Claude, Claude Code, Codex, ChatGPT, GPT, OpenAI, Anthropic, Cursor, Figma, Raycast, Telegram, Instagram, Notion, инпут, оверлей, стриминг, бэкенд, фронтенд."

    /// Старый инструкция-промпт (до 2026-06-03). Мигрируем его на глоссарий: инструкции
    /// whisper игнорирует, а упоминание «Продолжение следует» в нём само провоцировало эту
    /// галлюцинацию (negation модель не понимает).
    public static let legacyInstructionPrompt = "Пиши грамотный русский текст с естественной пунктуацией. Не ставь точку, если мысль явно не завершена. Делай абзацы только при смене темы, смысловом переходе или явной команде нового абзаца. Не добавляй фразы вроде «Продолжение следует», если их не произнесли."

    public var hasHotkeyConflict: Bool {
        toggleHotkey == pushToTalkHotkey
    }

    /// URL к VAD-модели Silero, если файл скачан в папку моделей.
    public func vadModelURL() -> URL? {
        let url = URL(fileURLWithPath: modelDirectoryPath)
            .appendingPathComponent("ggml-silero-v5.1.2.bin")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func modelURL() throws -> URL {
        guard let profile = ModelProfile.profile(id: selectedModelID) else {
            throw SettingsError.unknownModel(selectedModelID)
        }
        return URL(fileURLWithPath: modelDirectoryPath, isDirectory: true)
            .appendingPathComponent(profile.fileName)
    }
}

public enum SettingsError: Error, Equatable {
    case unknownModel(String)
}

public struct DictationUsageSummary: Equatable, Sendable {
    public let dictationCount: Int
    public let wordCount: Int
    public let durationSeconds: Double

    public init(dictationCount: Int, wordCount: Int, durationSeconds: Double) {
        self.dictationCount = dictationCount
        self.wordCount = wordCount
        self.durationSeconds = durationSeconds
    }

    public static let empty = DictationUsageSummary(dictationCount: 0, wordCount: 0, durationSeconds: 0)

    public static func make(from entries: [DictationEntry]) -> DictationUsageSummary {
        let words = entries.reduce(0) { total, entry in
            total + entry.text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
        }
        let duration = entries.reduce(0) { $0 + $1.durationSeconds }
        return DictationUsageSummary(
            dictationCount: entries.count,
            wordCount: words,
            durationSeconds: duration
        )
    }
}
