import Foundation
import LyraVoiceCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func testBuiltInProfilesExposeTurboAndLargeV3() {
    let profiles = ModelProfile.builtInProfiles

    expect(profiles.map(\.id) == ["tiny", "small", "medium", "turbo", "large-v3"], "profile ids should be ordered")
    expect(profiles[0].displayName == "Tiny", "tiny display name")
    expect(profiles[0].fileName == "ggml-tiny.bin", "tiny file name")
    expect(profiles[0].downloadURL.absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin", "tiny download url")
    expect(profiles[0].speedScore == 10, "tiny speed score")
    expect(profiles[0].accuracyScore == 2, "tiny accuracy score")
    expect(profiles[3].displayName == "Turbo", "turbo display name")
    expect(profiles[3].fileName == "ggml-large-v3-turbo.bin", "turbo file name")
    expect(profiles[3].downloadURL.absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin", "turbo download url")
    expect(profiles[3].priority == .speed, "turbo priority")
    expect(profiles[4].displayName == "Large v3", "large display name")
    expect(profiles[4].fileName == "ggml-large-v3.bin", "large file name")
    expect(profiles[4].downloadURL.absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin", "large download url")
    expect(profiles[4].priority == .accuracy, "large priority")
    expect(profiles[4].speedScore == 3, "large speed score")
    expect(profiles[4].accuracyScore == 10, "large accuracy score")
    expect(profiles[4].description.contains("русской"), "large description should be localized")
}

func testFindProfileByIdentifier() {
    expect(ModelProfile.profile(id: "turbo")?.fileName == "ggml-large-v3-turbo.bin", "find turbo")
    expect(ModelProfile.profile(id: "large-v3")?.fileName == "ggml-large-v3.bin", "find large")
    expect(ModelProfile.profile(id: "medium")?.fileName == "ggml-medium.bin", "find medium")
    expect(ModelProfile.profile(id: "parakeet") == nil, "unsupported profile should be nil")
}

func testNormalizesWhitespaceWithoutChangingMeaning() {
    let input = "  Привет,   это   тест.\n\n\nСледующая    строка.  "
    let output = TextPostProcessor.lightCleanup(input)

    expect(output == "Привет, это тест.\n\nСледующая строка.", "normalize whitespace")
}

func testKeepsIntentionalParagraphBreaks() {
    let input = "Первый абзац.\n\nВторой абзац.\n\n\n\nТретий абзац."
    let output = TextPostProcessor.lightCleanup(input)

    expect(output == "Первый абзац.\n\nВторой абзац.\n\nТретий абзац.", "keep paragraph breaks")
}

func testFormatsLongDictationIntoParagraphs() {
    let input = "Первое предложение. Второе предложение. Третье предложение. Четвертое предложение? Пятое предложение! Шестое предложение."
    let output = TextPostProcessor.dictationCleanup(input)

    expect(
        output == "Первое предложение. Второе предложение. Третье предложение. Четвертое предложение? Пятое предложение! Шестое предложение.",
        "long dictation should not be split by sentence count"
    )
}

func testAddsParagraphsOnSemanticTransitions() {
    let input = "Починили горячие клавиши. Теперь сочетания должны выглядеть аккуратно. Также нужно привести диктовку к читаемому виду. Лишние точки и слова-паразиты мешают воспринимать текст."
    let output = TextPostProcessor.dictationCleanup(input)

    expect(
        output == "Починили горячие клавиши. Теперь сочетания должны выглядеть аккуратно.\n\nТакже нужно привести диктовку к читаемому виду. Лишние точки и слова-паразиты мешают воспринимать текст.",
        "semantic transition should start a new paragraph, got: \(output)"
    )
}

func testKeepsShortDictationAsSingleParagraph() {
    // ≤3 предложений не дробим, даже если есть маркер — иначе абзац «просто так».
    let input = "Я проснулся. Выпил кофе. Также позавтракал."
    let output = TextPostProcessor.dictationCleanup(input)
    expect(
        output == "Я проснулся. Выпил кофе. Также позавтракал.",
        "short dictation should stay one paragraph, got: \(output)"
    )
}

func testStrongMarkerStartsNewParagraph() {
    let input = "Сделали первое. Сделали второе. Кроме того, добавили третье. И четвёртое."
    let output = TextPostProcessor.dictationCleanup(input)
    expect(
        output == "Сделали первое. Сделали второе.\n\nКроме того, добавили третье. И четвёртое.",
        "strong marker should start a new paragraph, got: \(output)"
    )
}

func testSplitsVeryLongWallOfText() {
    // Длинный монолог без маркеров не оставляем «простынёй»: страховочный разрыв.
    let input = "Раз. Два. Три. Четыре. Пять. Шесть. Семь. Восемь. Девять. Десять."
    let output = TextPostProcessor.dictationCleanup(input)
    expect(
        output == "Раз. Два. Три. Четыре. Пять. Шесть. Семь. Восемь.\n\nДевять. Десять.",
        "very long wall of text should get a safety break, got: \(output)"
    )
}

func testLocalLLMModelDefaults() {
    let model = LocalLLMModel.default
    expect(model.fileName == "Qwen2.5-3B-Instruct-Q4_K_M.gguf", "default llm model filename, got: \(model.fileName)")
    expect(model.downloadURL.absoluteString.hasSuffix(model.fileName), "download url points at the model file")
    let emptyDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    expect(model.isDownloaded(inModelDirectory: emptyDir) == false, "model should not be reported as downloaded in empty dir")
}

func testLocalLLMPolisherFallsBackToRulesWhenServerUnavailable() async throws {
    // Заведомо недоступный порт → сетевой запрос провалится → безопасный откат на правила.
    let endpoint = URL(string: "http://127.0.0.1:9/v1/chat/completions")!
    let polisher = LocalLLMPolisher(endpoint: endpoint, fallback: RulePolisher(), requestTimeout: 2)
    let result = try await polisher.polish("привет точка как дела")
    expect(result == "Привет. Как дела", "should fall back to rule polishing when server is down, got: \(result)")
}

func testRemovesSubtitleHallucinationTail() {
    let output = TextPostProcessor.lightCleanup("Нужно сохранить только продиктованный текст. Продолжение следует.")
    let creditsOutput = TextPostProcessor.lightCleanup("Это нормальная диктовка. Сделал Дима рожок.")

    expect(output == "Нужно сохранить только продиктованный текст.", "subtitle hallucination tail removed, got: \(output)")
    expect(creditsOutput == "Это нормальная диктовка.", "subtitle credits tail removed, got: \(creditsOutput)")
}

func testRemovesEditorSubtitleCredits() {
    // Самый частый русский whisper-артефакт — встречается в хвосте, середине и в начале.
    let tail = TextPostProcessor.lightCleanup("Проверим, как работает сервис. Редактор субтитров А.Семкин Корректор А.Егорова")
    let head = TextPostProcessor.stripHallucinations("Редактор субтитров А.Семкин Корректор А.Егорова\nОсновной текст диктовки.")
    let onlyCredits = TextPostProcessor.stripHallucinations("Субтитры подготовил Иван Иванов")

    expect(tail == "Проверим, как работает сервис.", "editor subtitle credits removed from tail, got: \(tail)")
    expect(head == "Основной текст диктовки.", "editor subtitle credits removed from head, got: \(head)")
    expect(onlyCredits.isEmpty, "pure credit hallucination collapses to empty, got: \(onlyCredits)")
}

func testNormalizesWhisperSegmentNewlines() {
    // warm-server идёт с `--split-on-word` → переносы whisper всегда на границе ЦЕЛЫХ слов,
    // CLI-путь с `-nt` переносов не содержит. Значит каждый перенос → пробел между словами.
    let wordWrap = TextPostProcessor.normalizeTranscriptNewlines("полностью пройдём потому\n что у нас есть")
    let leadingSpace = TextPostProcessor.normalizeTranscriptNewlines("как мы\n все вроде бы")
    let afterPunct = TextPostProcessor.normalizeTranscriptNewlines("нечетко все это пишет.\nЭто просто")
    // Регрессия на жалобу «слова слипаются»: подряд идущие границы слов (даже без ведущего
    // пробела, на случай если сервер его не поставил) НЕ должны слепляться.
    let noGlue = TextPostProcessor.normalizeTranscriptNewlines("надиктовываю\nкакое-то\nсообщение\nи все")

    expect(wordWrap == "полностью пройдём потому что у нас есть", "word-wrap newline → space, got: \(wordWrap)")
    expect(leadingSpace == "как мы все вроде бы", "between-word newline → single space, got: \(leadingSpace)")
    expect(afterPunct == "нечетко все это пишет. Это просто", "newline after punctuation → space, got: \(afterPunct)")
    expect(noGlue == "надиктовываю какое-то сообщение и все", "consecutive word newlines must not glue, got: \(noGlue)")
}

func testAppendAndReadHistoryEntriesNewestFirst() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try HistoryStore(directory: directory, retentionDays: 0)
    let first = DictationEntry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        createdAt: Date(timeIntervalSince1970: 100),
        modelID: "turbo",
        durationSeconds: 4.2,
        processingSeconds: 1.1,
        text: "Первый текст"
    )
    let second = DictationEntry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        createdAt: Date(timeIntervalSince1970: 200),
        modelID: "large-v3",
        durationSeconds: 7.0,
        processingSeconds: 3.4,
        text: "Второй текст"
    )

    try store.append(first)
    try store.append(second)

    let entries = try store.recent(limit: 10)
    expect(entries.map(\.id) == [second.id, first.id], "history newest first ids")
    expect(entries.map(\.text) == ["Второй текст", "Первый текст"], "history newest first text")
}

func testHistoryDeleteAndClear() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try HistoryStore(directory: directory, retentionDays: 0)
    let keep = DictationEntry(modelID: "turbo", durationSeconds: 1, processingSeconds: 1, text: "Оставить")
    let remove = DictationEntry(modelID: "turbo", durationSeconds: 1, processingSeconds: 1, text: "Удалить")
    try store.append(keep)
    try store.append(remove)

    try store.delete(id: remove.id)
    let afterDelete = try store.all()
    expect(afterDelete.map(\.id) == [keep.id], "delete removes only target entry")

    try store.clear()
    let afterClear = try store.all()
    expect(afterClear.isEmpty, "clear empties history")
}

func testHistorySearch() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = try HistoryStore(directory: dir, retentionDays: 0)
    try store.append(DictationEntry(modelID: "turbo", durationSeconds: 1, processingSeconds: 1, text: "Привет Claude"))
    try store.append(DictationEntry(modelID: "turbo", durationSeconds: 1, processingSeconds: 1, text: "Привет Codex"))
    try store.append(DictationEntry(modelID: "turbo", durationSeconds: 1, processingSeconds: 1, text: "Другая запись"))

    let claudeResults = try store.search(query: "Claude")
    expect(claudeResults.count == 1, "search finds exactly one Claude entry, got \(claudeResults.count)")
    expect(claudeResults.first?.text == "Привет Claude", "search returns correct entry")

    let privetResults = try store.search(query: "Привет")
    expect(privetResults.count == 2, "search finds two 'Привет' entries, got \(privetResults.count)")

    let emptyResults = try store.search(query: "Несуществующее")
    expect(emptyResults.isEmpty, "search returns empty for non-matching query")

    let allResults = try store.search(query: "")
    expect(allResults.count == 3, "empty query returns all entries, got \(allResults.count)")
}

func testRecentRespectsLimit() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try HistoryStore(directory: directory, retentionDays: 0)

    for index in 0..<3 {
        try store.append(DictationEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
            modelID: "turbo",
            durationSeconds: 1,
            processingSeconds: 1,
            text: "Text \(index)"
        ))
    }

    let recentTexts = try store.recent(limit: 2).map(\.text)
    expect(recentTexts == ["Text 2", "Text 1"], "history limit")
}

func testWhisperCommandBuildsCLIArguments() {
    let command = WhisperCommand(
        binaryURL: URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
        modelURL: URL(fileURLWithPath: "/models/ggml-large-v3-turbo.bin"),
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        language: "ru",
        initialPrompt: "Пиши русский текст с пунктуацией.",
        threads: 8,
        beamSize: 5
    )

    expect(command.executablePath == "/opt/homebrew/bin/whisper-cli", "whisper executable path")
    expect(command.arguments == [
        "-m", "/models/ggml-large-v3-turbo.bin",
        "-f", "/tmp/input.wav",
        "-l", "ru",
        "-t", "8",
        "-bs", "5",
        "-bo", "5",
        "--prompt", "Пиши русский текст с пунктуацией.",
        "--carry-initial-prompt",
        "-sns",
        "-nt",
        "-np"
    ], "whisper arguments")
}

func testDefaultSettingsUseLocalFreeModel() throws {
    let settings = AppSettings.defaultSettings()

    expect(settings.selectedModelID == "large-v3", "default model should be large-v3")
    expect(settings.language == "auto", "default language should be auto")
    expect(settings.interfaceLanguage == "auto", "default interface language should be automatic")
    expect(AppSettings.supportedInterfaceLanguages == ["ru", "en"], "supported interface languages should be centralized")
    expect(settings.mediaInterruptionMode == .pause, "media interruption default pause")
    expect(settings.polishLevel == .rules, "default polish level should be rules")
    expect(!settings.smartContextEnabled, "smart context should be privacy-off by default")
    expect(settings.toggleHotkey.keyCode == 49, "default toggle hotkey key code should be space")
    expect(settings.toggleHotkey.modifierFlags == ["control", "option"], "default toggle hotkey modifiers")
    expect(settings.toggleHotkey.displayText == "⌃ ⌥ Space", "default toggle hotkey display text")
    expect(settings.pushToTalkHotkey == .fn, "default hold hotkey should be Fn")
    expect(!settings.hasHotkeyConflict, "default hotkeys should not conflict")
    expect(settings.whisperBinaryPath == "/opt/homebrew/bin/whisper-cli", "default whisper binary path")
    expect(settings.modelDirectoryPath.hasSuffix("Library/Application Support/LyraVoice/Models"), "default model directory")
    // initial_prompt — это ГЛОССАРИЙ имён собственных (whisper не выполняет инструкции),
    // он должен содержать ключевые термины, а не указания по пунктуации.
    expect(settings.initialPrompt.contains("Lyra Voice"), "default prompt should be a glossary with key terms")
    expect(!settings.initialPrompt.contains("Продолжение следует"),
           "default prompt must NOT prime the subtitle hallucination")
}

func testLegacyInstructionPromptMigratesToGlossary() {
    let json = """
    {"selectedModelID":"turbo","language":"auto","initialPrompt":"\(AppSettings.legacyInstructionPrompt)"}
    """.data(using: .utf8)!
    let migrated = try! JSONDecoder().decode(AppSettings.self, from: json)
    expect(migrated.initialPrompt == AppSettings.defaultInitialPrompt,
           "legacy instruction prompt should migrate to glossary, got: \(migrated.initialPrompt)")

    // Кастомный промпт пользователя НЕ трогаем.
    let custom = """
    {"selectedModelID":"turbo","language":"auto","initialPrompt":"Мои термины: Foobar, Baz."}
    """.data(using: .utf8)!
    let kept = try! JSONDecoder().decode(AppSettings.self, from: custom)
    expect(kept.initialPrompt == "Мои термины: Foobar, Baz.", "custom prompt must be preserved, got: \(kept.initialPrompt)")
}

func testSmartContextMigratesLegacyContextToggles() {
    let activeFieldOnly = try! JSONDecoder().decode(AppSettings.self,
        from: #"{"screenContextEnabled":true,"clipboardContextEnabled":false}"#.data(using: .utf8)!)
    expect(activeFieldOnly.smartContextEnabled, "legacy active-field context should enable smart context")

    let clipboardOnly = try! JSONDecoder().decode(AppSettings.self,
        from: #"{"screenContextEnabled":false,"clipboardContextEnabled":true}"#.data(using: .utf8)!)
    expect(clipboardOnly.smartContextEnabled, "legacy clipboard context should enable smart context")

    let explicitOff = try! JSONDecoder().decode(AppSettings.self,
        from: #"{"smartContextEnabled":false,"screenContextEnabled":true,"clipboardContextEnabled":true}"#.data(using: .utf8)!)
    expect(!explicitOff.smartContextEnabled, "new smart context setting should override old split toggles")
}

func testSpokenLanguagesMigrationAndEffective() {
    // Старый settings.json с language="ru" → автоопределение off, [ru].
    let ru = try! JSONDecoder().decode(AppSettings.self, from: #"{"language":"ru"}"#.data(using: .utf8)!)
    expect(!ru.autoDetectLanguage && ru.spokenLanguages == ["ru"], "ru migrates to off+[ru]")
    expect(ru.effectiveTranscriptionLanguage == "ru", "effective for forced ru is ru")

    let auto = try! JSONDecoder().decode(AppSettings.self, from: #"{"language":"auto"}"#.data(using: .utf8)!)
    expect(auto.autoDetectLanguage && auto.spokenLanguages.isEmpty, "auto migrates to on+[]")
    expect(auto.effectiveTranscriptionLanguage == "auto", "effective for auto is auto")

    // Новый формат: авто off, [en, ru] → основной (первый) en.
    let multi = try! JSONDecoder().decode(AppSettings.self,
        from: #"{"autoDetectLanguage":false,"spokenLanguages":["en","ru"]}"#.data(using: .utf8)!)
    expect(multi.effectiveTranscriptionLanguage == "en", "effective primary is first selected, got: \(multi.effectiveTranscriptionLanguage)")

    // Авто on перекрывает выбор → auto.
    let multiAuto = try! JSONDecoder().decode(AppSettings.self,
        from: #"{"autoDetectLanguage":true,"spokenLanguages":["en","ru"]}"#.data(using: .utf8)!)
    expect(multiAuto.effectiveTranscriptionLanguage == "auto", "auto on → auto regardless of selection")
}

func testAutomaticInterfaceLanguageResolvesFromPreferredLanguages() {
    expect(
        AppSettings.resolvedInterfaceLanguage("auto", preferredLanguages: ["ru-RU", "en-US"]) == "ru",
        "auto interface language should use the first supported system language"
    )
    expect(
        AppSettings.resolvedInterfaceLanguage("auto", preferredLanguages: ["fr-FR", "en-US", "ru-RU"]) == "en",
        "auto interface language should skip unsupported languages and use the first supported fallback"
    )
    expect(
        AppSettings.resolvedInterfaceLanguage("auto", preferredLanguages: ["fr-FR"]) == "en",
        "auto interface language should fall back to English when no preferred language is supported"
    )
    expect(
        AppSettings.resolvedInterfaceLanguage("ru", preferredLanguages: ["en-US"]) == "ru",
        "explicit interface language should ignore system preferences"
    )
    expect(
        AppSettings.resolvedInterfaceLanguage("de", preferredLanguages: ["ru-RU"]) == "en",
        "unsupported explicit interface language should fall back to English"
    )
}

func testInterfaceLanguageNamesIncludeAutomaticMode() {
    L.set("ru")
    expect(L.languageName("auto") == "Авто (по системе)", "auto language name should be localized in Russian")
    expect(L.languageName("ru") == "Русский", "Russian language name")
    expect(L.languageName("en") == "English", "English language name")

    L.set("en")
    expect(L.languageName("auto") == "Auto (System)", "auto language name should be localized in English")

    L.set("ru")
}

func testSettingsMigratesLegacyHotkeyToToggleAndKeepsHoldFn() throws {
    let legacyJSON = """
    {
      "selectedModelID": "large-v3",
      "language": "auto",
      "initialPrompt": "Промпт",
      "hotkeyMode": "pushToTalk",
      "hotkey": { "keyCode": 36, "modifierFlags": ["command", "shift"] },
      "whisperBinaryPath": "/opt/homebrew/bin/whisper-cli",
      "modelDirectoryPath": "/tmp/models"
    }
    """.data(using: .utf8)!

    let settings = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)

    expect(settings.toggleHotkey.displayText == "⌘ ⇧ Return", "legacy hotkey should become start-stop hotkey")
    expect(settings.pushToTalkHotkey == .fn, "hold hotkey should default to Fn after legacy migration")
    expect(!settings.hasHotkeyConflict, "legacy migration should avoid conflicts")
}

func testSettingsDetectsDuplicateDictationHotkeys() throws {
    var settings = AppSettings.defaultSettings()

    settings.pushToTalkHotkey = settings.toggleHotkey

    expect(settings.hasHotkeyConflict, "duplicate start-stop and hold hotkeys should be a conflict")
}

func testMediaInterruptionModePersistsAndMigratesFromPauseToggle() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    var settings = AppSettings.defaultSettings()
    settings.mediaInterruptionMode = .duck

    let data = try encoder.encode(settings)
    let loaded = try decoder.decode(AppSettings.self, from: data)
    expect(loaded.mediaInterruptionMode == .duck, "media mode should persist")

    let legacyJSON = """
    {
      "selectedModelID": "large-v3",
      "language": "auto",
      "initialPrompt": "",
      "hotkeyMode": "toggle",
      "hotkey": { "keyCode": 49, "modifierFlags": ["control", "option"] },
      "whisperBinaryPath": "/opt/homebrew/bin/whisper-cli",
      "modelDirectoryPath": "/tmp/models",
      "pauseMediaWhileRecording": false
    }
    """.data(using: .utf8)!

    let migrated = try decoder.decode(AppSettings.self, from: legacyJSON)
    expect(migrated.mediaInterruptionMode == .none, "legacy disabled pause should migrate to none")
}

func testAppBrandUsesLyraVoiceName() {
    expect(AppBrand.displayName == "Lyra Voice", "app display name")
    expect(AppBrand.menuBarTitle == "LV", "menu bar title")
    expect(AppBrand.executableName == "LyraVoice", "visible executable name")
    expect(AppBrand.bundleIdentifier == "local.lyravoice.app", "bundle identifier rebranded")
    expect(AppBrand.applicationSupportDirectoryName == "LyraVoice", "support directory rebranded")
    expect(!AppBrand.displayName.contains("WhisperKey"), "no legacy brand in display name")
}

func testAppBrandDeclaresLogoAssets() {
    expect(AppBrand.appIconFileName == "LyraVoice.icns", "app icon file name")
    expect(AppBrand.logoImageFileName == "LyraVoiceMark.png", "logo image file name")

    let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Assets/Brand", isDirectory: true)
    expect(FileManager.default.fileExists(atPath: assets.appendingPathComponent(AppBrand.appIconFileName).path), "app icon asset exists")
    expect(FileManager.default.fileExists(atPath: assets.appendingPathComponent(AppBrand.logoImageFileName).path), "logo image asset exists")
}

func testFunctionKeyHotkeyDisplaysAsFn() {
    let hotkey = Hotkey.fn
    expect(hotkey.keyCode == Hotkey.functionKeyCode, "fn key code")
    expect(hotkey.modifierFlags == ["function"], "fn modifier")
    expect(hotkey.displayText == "Fn", "fn display text")
}

func testModifierOnlyKeyCodesAreNotCapturableHotkeys() {
    expect(Hotkey.isModifierOnlyKeyCode(54), "right command key code should be modifier-only")
    expect(Hotkey.isModifierOnlyKeyCode(55), "left command key code should be modifier-only")
    expect(Hotkey.isModifierOnlyKeyCode(56), "left shift key code should be modifier-only")
    expect(Hotkey.isModifierOnlyKeyCode(58), "left option key code should be modifier-only")
    expect(Hotkey.isModifierOnlyKeyCode(59), "left control key code should be modifier-only")
    expect(Hotkey.isModifierOnlyKeyCode(60), "right shift key code should be modifier-only")
    expect(Hotkey.isModifierOnlyKeyCode(61), "right option key code should be modifier-only")
    expect(Hotkey.isModifierOnlyKeyCode(62), "right control key code should be modifier-only")
    expect(!Hotkey.isModifierOnlyKeyCode(40), "K key code should stay capturable")
    expect(!Hotkey.isModifierOnlyKeyCode(49), "Space key code should stay capturable")
}

func testDictationUsageSummaryCountsWordsAndDuration() {
    let entries = [
        DictationEntry(modelID: "large-v3", durationSeconds: 10, processingSeconds: 1, text: "Привет мир"),
        DictationEntry(modelID: "turbo", durationSeconds: 5.5, processingSeconds: 1, text: "Ещё одна строка")
    ]
    let summary = DictationUsageSummary.make(from: entries)
    expect(summary.dictationCount == 2, "summary count")
    expect(summary.wordCount == 5, "summary words")
    expect(summary.durationSeconds == 15.5, "summary duration")
}

func testSettingsStoreSavesAndLoadsSettings() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try SettingsStore(directory: directory)
    var settings = AppSettings.defaultSettings()
    settings.selectedModelID = "large-v3"
    settings.language = "auto"
    settings.toggleHotkey = Hotkey(keyCode: 36, modifierFlags: ["command", "shift"])
    settings.pushToTalkHotkey = Hotkey(keyCode: 40, modifierFlags: ["control", "option"])

    try store.save(settings)

    let loaded = try store.load()
    expect(loaded.selectedModelID == "large-v3", "settings model should persist")
    expect(loaded.language == "auto", "settings language should persist")
    expect(loaded.toggleHotkey.displayText == "⌘ ⇧ Return", "settings toggle hotkey should persist")
    expect(loaded.pushToTalkHotkey.displayText == "⌃ ⌥ K", "settings hold hotkey should persist")
}

func testSettingsDecodeFallsBackFromModifierOnlyHotkey() throws {
    let json = """
    {
      "selectedModelID": "large-v3",
      "language": "auto",
      "initialPrompt": "Промпт",
      "hotkeyMode": "toggle",
      "hotkey": { "keyCode": 58, "modifierFlags": ["option"] },
      "whisperBinaryPath": "/opt/homebrew/bin/whisper-cli",
      "modelDirectoryPath": "/tmp/models"
    }
    """.data(using: .utf8)!

    let settings = try JSONDecoder().decode(AppSettings.self, from: json)

    expect(settings.toggleHotkey.keyCode == 49, "modifier-only persisted hotkey should fall back to default key")
    expect(settings.toggleHotkey.displayText == "⌃ ⌥ Space", "modifier-only persisted hotkey should not display Key 58")
}

func testProcessRunnerReturnsStandardOutput() throws {
    let runner = ProcessRunner()
    let result = try runner.run(
        executablePath: "/bin/echo",
        arguments: ["  Привет,   мир.  "],
        timeoutSeconds: 5
    )

    expect(result.exitCode == 0, "echo exit code")
    expect(TextPostProcessor.lightCleanup(result.standardOutput) == "Привет, мир.", "echo output")
    expect(result.standardError.isEmpty, "echo stderr should be empty")
}

func testWhisperCLITranscriberUsesCommandOutput() throws {
    let transcriber = WhisperCLITranscriber(runner: ProcessRunner())
    let command = WhisperCommand(
        binaryURL: URL(fileURLWithPath: "/bin/echo"),
        modelURL: URL(fileURLWithPath: "/models/model.bin"),
        audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
        language: "ru",
        extraArguments: ["Привет,   тест."]
    )

    let text = try transcriber.transcribe(command: command, timeoutSeconds: 5)

    expect(text.contains("Привет, тест."), "transcriber should clean process stdout")
}

func testControlPanelStateExposesExpectedActions() {
    let idle = ControlPanelState.idle
    expect(idle.statusTitle == "Готово", "idle title")
    expect(idle.canStartRecording, "idle can start recording")
    expect(!idle.canStopRecording, "idle cannot stop recording")
    expect(!idle.canCancelRecording, "idle cannot cancel recording")
    expect(idle.canRunTestAudio, "idle can run test audio")

    let recording = ControlPanelState.recording(seconds: 3)
    expect(recording.statusTitle == "Слушаю", "recording title")
    expect(recording.statusDetail == "Записано 3 c", "recording detail")
    expect(!recording.canStartRecording, "recording cannot start recording")
    expect(recording.canStopRecording, "recording can stop recording")
    expect(recording.canCancelRecording, "recording can cancel recording")
    expect(!recording.canRunTestAudio, "recording cannot run test audio")

    let processing = ControlPanelState.processing(modelName: "Turbo")
    expect(processing.statusTitle == "Распознаю", "processing title")
    expect(processing.statusDetail == "Распознаю моделью Turbo", "processing detail")
    expect(!processing.canStartRecording, "processing cannot start recording")
    expect(!processing.canStopRecording, "processing cannot stop recording")
    expect(!processing.canCancelRecording, "processing cannot cancel recording")
    expect(!processing.canRunTestAudio, "processing cannot run test audio")

    let copied = ControlPanelState.copied
    expect(copied.statusTitle == "Скопировано", "copied title")
    expect(copied.canStartRecording, "copied can start recording")
    expect(!copied.canStopRecording, "copied cannot stop recording")

    let error = ControlPanelState.error("Microphone access is required.")
    expect(error.statusTitle == "Нужно внимание", "error title")
    expect(error.statusDetail == "Microphone access is required.", "error detail")
    expect(error.canStartRecording, "error can start recording")
}

func testControlPanelNavigationMatchesReferenceIA() {
    let sections = ControlPanelSection.allCases

    expect(
        sections.map(\.rawValue) == ["home", "modes", "vocabulary", "models", "sound", "system", "history"],
        "control panel sections should match the reference IA"
    )
    expect(sections.map(\.title).contains("Распознавание") == false, "old Recognition section should be removed")
    expect(sections.map(\.title).contains("Текст и полировка") == false, "old Text & polish section should be removed")
    expect(ControlPanelSection.models.subtitle.lowercased().contains("полиров"), "Models should own polish controls")
    expect(ControlPanelSection.vocabulary.subtitle.lowercased().contains("словар"), "Vocabulary should own dictionary controls")
    expect(ControlPanelSection.sound.subtitle.contains("Микрофон"), "Sound should own microphone controls")
}

func testHomeDashboardDoesNotDuplicatePrimaryUsageMetrics() throws {
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/ControlPanelWindowController.swift")
    let source = try String(contentsOf: sourceURL)

    expect(
        !source.contains("usagePeriodDictationsLabel"),
        "Home activity card should not duplicate dictation count already shown in the top lifetime tiles"
    )
    expect(
        !source.contains("usagePeriodWordsLabel"),
        "Home activity card should not duplicate word count already shown in the top lifetime tiles"
    )
    expect(
        source.contains("dailyUsage.map(\\.dictationCount).max()"),
        "activity chart should visualize dictation activity rather than word volume"
    )
}

func testControlPanelUsesRestrainedReferenceShell() throws {
    let panelURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/ControlPanelWindowController.swift")
    let panel = try String(contentsOf: panelURL)
    let designURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/DesignSystem.swift")
    let design = try String(contentsOf: designURL)

    expect(panel.contains("SidebarPanelView()"), "left sidebar should remain a Liquid Glass sidebar panel")
    expect(panel.contains("makeUpgradeCard()"), "sidebar should reserve an Upgrade to Pro card for the paid tier")
    expect(panel.contains("makeAccountRow()"), "sidebar should reserve a bottom account row")
    expect(panel.contains("showsSidebarFutureSlots = false"), "future Pro/account sidebar slots should remain hidden until account and paid tier are implemented")
    expect(panel.contains("if showsSidebarFutureSlots"), "reserved Pro/account sidebar slots should be feature-gated, not deleted")
    expect(panel.contains("selectedAccentLayer"), "selected sidebar item should use a restrained reference-style accent layer")
    expect(!design.contains("private let brandGradient"), "primary buttons should not use the old cyan-violet AI gradient layer")
}

func testRecordingOverlayWaveformIsVisiblyResponsive() throws {
    let overlayURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/OverlayView.swift")
    let overlay = try String(contentsOf: overlayURL)

    expect(overlay.contains("private let barWidth: CGFloat = 2"), "recording overlay waveform should keep the thin refined bars")
    expect(overlay.contains("private let minBar: CGFloat = 2"), "recording overlay idle state should stay as small dots")
    expect(overlay.contains("private let noiseGate"), "recording overlay should ignore low ambient noise before showing voice spikes")
    expect(overlay.contains("renderIdleDots"), "recording overlay silence should settle into even dots")
    expect(overlay.contains("hidePillButtons()"), "recording overlay should not show extra accept/cancel buttons")
}

func testAppDelegateObservesSystemLocaleOnlyForAutomaticInterfaceLanguage() throws {
    let appDelegateURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/AppDelegate.swift")
    let source = try String(contentsOf: appDelegateURL)

    expect(
        source.contains("NSLocale.currentLocaleDidChangeNotification"),
        "AppDelegate should observe system locale changes"
    )
    expect(
        source.contains("settings.interfaceLanguage == AppSettings.automaticInterfaceLanguage"),
        "system locale observer should react only when interface language is auto"
    )
    expect(
        source.contains("AppSettings.resolvedInterfaceLanguage(settings.interfaceLanguage"),
        "AppDelegate should apply resolved interface language rather than the stored mode directly"
    )
}

func testAppDelegateDoesNotPersistSensitiveContext() throws {
    let appDelegateURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/AppDelegate.swift")
    let source = try String(contentsOf: appDelegateURL)

    expect(
        source.contains("!appContext.isSensitive"),
        "recording archive should be gated away from sensitive context"
    )
    expect(
        source.contains("history append skipped reason=sensitiveContext"),
        "history append should be skipped for sensitive context"
    )
    expect(
        source.contains("usage stats record skipped reason=sensitiveContext"),
        "usage stats should not count sensitive dictation content"
    )
}

func testModelProfilesExposeInterfaceCopy() {
    let turbo = ModelProfile.profile(id: "turbo")!
    let large = ModelProfile.profile(id: "large-v3")!

    expect(turbo.readyMessage.contains("готова"), "turbo ready message should be localized")
    expect(large.readyMessage.contains("точность 10/10"), "large ready message should explain accuracy")
    expect(turbo.missingMessage.contains("Turbo"), "turbo missing message should name model")
    expect(large.missingMessage.contains("Large v3"), "large missing message should name model")
    expect(turbo.menuTitle.contains("скорость 8/10"), "turbo menu title should use ten point scale")
}

func testProcessRunnerHandlesLargeOutputWithoutDeadlock() throws {
    // Вывод заведомо больше буфера пайпа (~64 КБ). Старая реализация читала
    // пайп только после завершения процесса и зависала здесь до таймаута.
    let runner = ProcessRunner()
    let lineCount = 50_000
    let result = try runner.run(
        executablePath: "/usr/bin/seq",
        arguments: ["1", "\(lineCount)"],
        timeoutSeconds: 30
    )

    expect(result.exitCode == 0, "seq should exit cleanly")
    let lines = result.standardOutput.split(separator: "\n")
    expect(lines.count == lineCount, "all \(lineCount) lines should be captured, got \(lines.count)")
    expect(lines.last == "\(lineCount)", "last line should be \(lineCount)")
}

func testRemovesServiceTagsAndConsecutiveDuplicates() {
    let withTags = TextPostProcessor.lightCleanup("Привет [BLANK_AUDIO] мир .")
    expect(withTags == "Привет мир.", "bracket tags and space-before-punct removed, got: \(withTags)")

    let withDuplicates = TextPostProcessor.dictationCleanup(
        "Спасибо за внимание. Спасибо за внимание. Спасибо за внимание."
    )
    expect(withDuplicates == "Спасибо за внимание.", "consecutive duplicate sentences collapsed, got: \(withDuplicates)")
}

func testOverlayMetricsStayCompact() {
    expect(OverlayMetrics.pushToTalkSize.width == 66, "push-to-talk overlay width")
    expect(OverlayMetrics.toggleSize.width == 100, "toggle overlay width")
    expect(OverlayMetrics.pushToTalkSize.width < OverlayMetrics.toggleSize.width,
           "push-to-talk overlay is narrower than toggle")
    expect(OverlayMetrics.size == OverlayMetrics.toggleSize, "legacy size maps to toggle")
    expect(OverlayMetrics.cornerRadius == 13, "overlay should be a full pill (half of height)")
    expect(OverlayMetrics.cornerRadius == OverlayMetrics.toggleSize.height / 2,
           "corner radius equals half height — full capsule")
    expect(OverlayMetrics.buttonSize == 20, "overlay buttons should stay compact")
    expect(OverlayMetrics.bottomOffset == 28, "overlay should sit at bottom edge")
    // Streaming panel — расширенная капсула с живым текстом
    expect(OverlayMetrics.streamingSize.width == 300, "streaming panel width")
    expect(OverlayMetrics.streamingSize.height == 104, "streaming panel height (3 lines + air)")
    expect(OverlayMetrics.streamingSize.width > OverlayMetrics.toggleSize.width,
           "streaming panel is wider than toggle pill")
}

func testDictionaryEditorKeepsInputAboveSeparatedEntries() throws {
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/DictionaryEditorView.swift")
    let source = try String(contentsOf: sourceURL)

    expect(
        source.contains("NSStackView(views: [addRow, entriesContainer])"),
        "dictionary input row should stay above the entries list"
    )
    expect(
        source.contains("private let entriesContainer"),
        "dictionary entries should live in a separate visual container"
    )
    expect(
        !source.contains("NSStackView(views: [listStack, addRow])"),
        "dictionary entries should not push the input row downward"
    )
}

func testMicrophonePermissionErrorUsesTransientOverlay() throws {
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/AppDelegate.swift")
    let source = try String(contentsOf: sourceURL)
    let stuckOverlayPattern = """
                setControlPanelState(.error("Microphone access is required. Open Settings."))
                overlayController.show(state: .error("Microphone access is required. Open Settings."))
"""

    expect(
        !source.contains(stuckOverlayPattern),
        "microphone permission errors should not show a permanent red overlay"
    )
    expect(
        source.contains("showTransientError(controlMessage: \"Microphone access is required. Open Settings.\""),
        "microphone permission errors should go through transient overlay helper"
    )
}

func testAudioRecorderKeepsLegacyFallback() throws {
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/AudioRecorder.swift")
    let source = try String(contentsOf: sourceURL)

    expect(
        source.contains("startFallbackRecording"),
        "AudioRecorder should fall back to AVAudioRecorder if AVAudioEngine cannot start"
    )
    expect(
        source.contains("case fallback(AVAudioRecorder)"),
        "AudioRecorder should track fallback backend explicitly"
    )
}

func testDictationPipelineWritesDiagnostics() throws {
    let appDelegateURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/AppDelegate.swift")
    let appDelegateSource = try String(contentsOf: appDelegateURL)
    let recorderURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/AudioRecorder.swift")
    let recorderSource = try String(contentsOf: recorderURL)
    let diagnosticsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/DiagnosticsLog.swift")

    expect(
        FileManager.default.fileExists(atPath: diagnosticsURL.path),
        "dictation failures should have an app-side diagnostics log"
    )
    expect(
        appDelegateSource.contains("DiagnosticsLog.write(\"startRecording requested"),
        "startRecording should log pipeline entry"
    )
    expect(
        appDelegateSource.contains("DiagnosticsLog.write(\"recording stopped"),
        "stopAndTranscribeRecording should log recorded audio metadata"
    )
    expect(
        appDelegateSource.contains("DiagnosticsLog.write(\"transcribe finished"),
        "transcription should log successful completion metadata"
    )
    expect(
        recorderSource.contains("activeBackendName"),
        "AudioRecorder should expose which backend is active for diagnostics"
    )
}

func testAudioSettingsExposeMediaModeSelector() throws {
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/ControlPanelWindowController.swift")
    let source = try String(contentsOf: sourceURL)

    expect(
        source.contains("mediaInterruptionSelector"),
        "audio settings should use a selector for media handling modes"
    )
    expect(
        source.contains("MediaInterruptionMode.duck.rawValue"),
        "audio settings should expose a duck/mute option"
    )
    expect(
        source.contains("makeSoundCard()"),
        "media handling should live in the Sound settings page"
    )
}

func testControlButtonRadiiStayModerate() throws {
    let designSystemURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/DesignSystem.swift")
    let designSystem = try String(contentsOf: designSystemURL)
    let overlayURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/OverlayView.swift")
    let overlay = try String(contentsOf: overlayURL)
    let resultCardURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/ResultCardController.swift")
    let resultCard = try String(contentsOf: resultCardURL)

    expect(designSystem.contains("static let control = 9.0"), "main controls should use 9pt radius (менее скруглённый, как у конкурентов)")
    expect(!overlay.contains("min(18"), "overlay icon buttons should not cap at 18pt")
    expect(!resultCard.contains("min(18"), "result card icon buttons should not cap at 18pt")
}

func testMicrophonePermissionUsesAudioRecordingAPI() throws {
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/LyraVoiceApp/MicrophonePermission.swift")
    let source = try String(contentsOf: sourceURL)

    expect(
        source.contains("AVAudioApplication.shared.recordPermission"),
        "microphone permission should use the AVAudio recording permission API on macOS 14+"
    )
    expect(
        source.contains("AVCaptureDevice.authorizationStatus(for: .audio)"),
        "microphone permission should keep an AVCapture fallback for older macOS"
    )
}

func testDevAppSigningIncludesMicrophoneEntitlement() throws {
    let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("scripts/build-dev-app.sh")
    let script = try String(contentsOf: scriptURL)
    let entitlementsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("LyraVoice.entitlements")
    let entitlements = try String(contentsOf: entitlementsURL)

    expect(
        script.contains("--entitlements \"$ENTITLEMENTS_FILE\""),
        "dev app signing should include the entitlements file"
    )
    expect(
        entitlements.contains("com.apple.security.device.audio-input"),
        "hardened runtime app should declare microphone entitlement"
    )
}

func testVoiceCommandsAndFillersAndDictionary() async throws {
    let commands = TextPostProcessor.applyVoiceCommands("Привет новый абзац Как дела запятая друг")
    expect(commands.contains("\n\n"), "новый абзац -> разрыв, got: \(commands)")
    expect(commands.contains(","), "запятая -> ',' got: \(commands)")

    // Консервативная чистка: убираем заминки и однозначные тики, но НЕ трогаем смысловые слова.
    let fillers = TextPostProcessor.removeFillerWords("Эээ это так сказать важно мм")
    expect(!fillers.lowercased().contains("эээ"), "hesitation 'эээ' removed, got: \(fillers)")
    expect(!fillers.lowercased().contains("так сказать"), "filler 'так сказать' removed, got: \(fillers)")
    expect(!fillers.contains(" мм"), "hesitation 'мм' removed, got: \(fillers)")
    expect(fillers.lowercased().contains("важно"), "meaningful word kept, got: \(fillers)")

    // Расширенный список (2026-06-12): дополнительные формульные хеджи без смысловой нагрузки.
    let extraFillers = TextPostProcessor.removeFillerWords(
        "Грубо говоря, это что называется баг, как говорится, если можно так сказать, критичный")
    for phrase in ["грубо говоря", "что называется", "как говорится", "если можно так сказать"] {
        expect(!extraFillers.lowercased().contains(phrase), "filler '\(phrase)' removed, got: \(extraFillers)")
    }
    expect(extraFillers.lowercased().contains("баг") && extraFillers.lowercased().contains("критичный"),
           "meaningful words kept, got: \(extraFillers)")

    // Смысловые слова и реальные слова с эам-буквами НЕ удаляются.
    let kept = TextPostProcessor.removeFillerWords("Мама сказала что это значит вообще другое")
    expect(kept.contains("Мама"), "real word 'Мама' must NOT be eaten, got: \(kept)")
    expect(kept.contains("значит") && kept.contains("вообще"), "meaning-bearing words kept, got: \(kept)")

    let duplicatePunctuation = try await RulePolisher().polish("привет точка. как дела запятая, друг")
    expect(duplicatePunctuation == "Привет. Как дела, друг", "duplicate voice punctuation collapsed, got: \(duplicatePunctuation)")

    let replaced = TextPostProcessor.applyReplacements("Открой джипити", [(from: "джипити", to: "GPT")])
    expect(replaced == "Открой GPT", "dictionary replacement applied, got: \(replaced)")

    let polished = try await RulePolisher(
        dictionary: [DictionaryEntry(from: "джипити", to: "GPT")]
    ).polish("привет джипити новая строка как дела")
    expect(polished.hasPrefix("Привет"), "first letter capitalized, got: \(polished)")
    expect(polished.contains("GPT"), "dictionary applied in polisher, got: \(polished)")
    expect(polished.contains("\n"), "новая строка -> перенос, got: \(polished)")
}

func testCorrectionCommands() {
    // «зачеркни последнее слово X» → удаляет слово ПЕРЕД командой, оставляет X.
    let lastWord = TextPostProcessor.applyCorrectionCommands("Купи молоко зачеркни последнее слово хлеб")
    expect(lastWord == "Купи хлеб", "'зачеркни последнее слово' drops preceding word, got: \(lastWord)")

    // Голая «зачеркни X» — то же самое, без «последнее слово».
    let bareWord = TextPostProcessor.applyCorrectionCommands("Купи яблоки зачеркни апельсины")
    expect(bareWord == "Купи апельсины", "bare 'зачеркни' drops preceding word, got: \(bareWord)")

    // «Отставить» отменяет предыдущее ПРЕДЛОЖЕНИЕ целиком.
    let cancelSentence = TextPostProcessor.applyCorrectionCommands("Завтра встреча в офисе. Отставить. Завтра встреча дома.")
    expect(cancelSentence == "Завтра встреча дома.", "'отставить' drops the previous sentence, got: \(cancelSentence)")

    // «зачеркни последнее предложение» — то же явной командой.
    let cancelExplicit = TextPostProcessor.applyCorrectionCommands("Это первое предложение. Зачеркни последнее предложение. Это второе предложение.")
    expect(cancelExplicit == "Это второе предложение.", "'зачеркни последнее предложение' drops it, got: \(cancelExplicit)")

    // Нормальный текст без команд не трогается.
    let untouched = TextPostProcessor.applyCorrectionCommands("Просто обычный текст без команд")
    expect(untouched == "Просто обычный текст без команд", "text without commands stays intact, got: \(untouched)")
}

func testQuoteVoiceCommands() async throws {
    // «открыть/закрыть кавычки» → «текст» БЕЗ паразитных пробелов внутри кавычек.
    let polished = try await RulePolisher().polish("он сказал открыть кавычки привет закрыть кавычки и ушел")
    expect(polished.contains("«привет»"), "quote command must not leave stray spaces, got: \(polished)")
    expect(!polished.contains("« ") && !polished.contains(" »"), "no space after « or before », got: \(polished)")
}

func testBuiltInVocabularyUsesCanonicalProductNames() async throws {
    let polished = try await RulePolisher().polish(
        "открой клод и кодекс потом чат джипити и опен эй ай"
    )

    expect(polished == "Открой Claude и Codex потом ChatGPT и OpenAI",
           "built-in AI/product vocabulary should use canonical names, got: \(polished)")
}

func testBuiltInVocabularyDisambiguatesClaudeCloudAndICloud() async throws {
    let cloud = try await RulePolisher().polish("включи cloud синхронизацию")
    expect(cloud == "Включи Cloud синхронизацию",
           "spoken Cloud should stay Cloud and not become Claude, got: \(cloud)")

    let iCloud = try await RulePolisher().polish("открой ай клауд")
    expect(iCloud == "Открой iCloud",
           "spoken iCloud should use canonical Apple casing, got: \(iCloud)")

    let claudeCode = try await RulePolisher().polish("открой клод козе")
    expect(claudeCode == "Открой Claude Code",
           "common ASR misspelling 'Клод Козе' should normalize to Claude Code, got: \(claudeCode)")
}

func testUserDictionaryOverridesBuiltInVocabulary() async throws {
    let polished = try await RulePolisher(
        dictionary: [DictionaryEntry(from: "клод", to: "Клод")]
    ).polish("открой клод и кодекс")

    expect(polished == "Открой Клод и Codex",
           "user vocabulary should override built-in vocabulary for the same trigger, got: \(polished)")
}

func testExplicitNumberedListFormatting() async throws {
    let polished = try await RulePolisher().polish(
        "пункт один купить молоко пункт два написать кодекс пункт три проверить клод"
    )

    expect(
        polished == "1. Купить молоко\n2. Написать Codex\n3. Проверить Claude",
        "explicit пункт один/два/три dictation should become a numbered list, got: \(polished)"
    )
}

func testOrdinalMarkersBecomeNumberedList() async throws {
    let polished = try await RulePolisher().polish(
        "во первых купить молоко во вторых написать кодекс"
    )

    expect(
        polished == "1. Купить молоко\n2. Написать Codex",
        "во-первых/во-вторых dictation should become a numbered list, got: \(polished)"
    )
}

func testHyphenDashAndPlaceVocabularyFormatting() async throws {
    let polished = try await RulePolisher().polish("нью йорк тире это город")

    expect(polished == "Нью-Йорк — это город",
           "place vocabulary and spoken dash should format cleanly, got: \(polished)")
}

func testDatesAndMoneyAreNormalizedConservatively() async throws {
    let polished = try await RulePolisher().polish(
        "встреча пятнадцатое января две тысячи двадцать шестого года бюджет двадцать долларов"
    )

    expect(
        polished == "Встреча 15 января 2026 г. бюджет $20",
        "spoken date and dollar amount should be normalized, got: \(polished)"
    )
}

func testTargetAppContextProfiles() {
    let mail = AppContextProfile.profile(
        bundleIdentifier: "com.apple.mail",
        localizedName: "Mail"
    )
    expect(mail.format == .email, "Mail should use email formatting")
    expect(mail.displayName == "Mail", "Mail profile display name")

    let terminal = AppContextProfile.profile(
        bundleIdentifier: "com.apple.Terminal",
        localizedName: "Terminal"
    )
    expect(terminal.format == .terminalCommand, "Terminal should use terminal command formatting")

    let unknown = AppContextProfile.profile(
        bundleIdentifier: "com.example.unknown",
        localizedName: "Unknown"
    )
    expect(unknown.format == .plainText, "unknown apps should use plain text formatting")
}

func testScreenContextRefinesTargetFormat() {
    let secure = ScreenContextSnapshot(
        focusedRole: "AXTextField",
        focusedSubrole: "AXSecureTextField",
        focusedTitle: "Password",
        focusedValueSnippet: "should-not-be-kept",
        selectedTextSnippet: "should-not-be-kept",
        clipboardTextSnippet: "should-not-be-kept",
        textBeforeCursorSnippet: "should-not-be-kept",
        textAfterCursorSnippet: "should-not-be-kept",
        isSecureTextEntry: true
    )
    expect(secure.redactedForPrivacy().focusedValueSnippet == nil, "secure value should be redacted")
    expect(secure.redactedForPrivacy().selectedTextSnippet == nil, "secure selection should be redacted")
    expect(secure.redactedForPrivacy().clipboardTextSnippet == nil, "secure clipboard should be redacted")
    expect(secure.redactedForPrivacy().textBeforeCursorSnippet == nil, "secure text before cursor should be redacted")
    expect(secure.redactedForPrivacy().textAfterCursorSnippet == nil, "secure text after cursor should be redacted")

    let password = AppContextProfile.profile(
        bundleIdentifier: "com.apple.Safari",
        localizedName: "Safari",
        screenContext: secure
    )
    expect(password.format == .password, "secure text fields should use password-safe formatting")
    expect(password.isSensitive, "password context should be marked sensitive")
    expect(password.screenContext?.focusedValueSnippet == nil, "profile should not retain secure value snippets")

    let url = AppContextProfile.profile(
        bundleIdentifier: "com.apple.Safari",
        localizedName: "Safari",
        screenContext: ScreenContextSnapshot(
            focusedRole: "AXTextField",
            focusedTitle: "Address",
            focusedValueSnippet: "https://example.com/docs"
        )
    )
    expect(url.format == .url, "URL/address fields should use URL formatting")

    let search = AppContextProfile.profile(
        bundleIdentifier: "com.apple.Safari",
        localizedName: "Safari",
        screenContext: ScreenContextSnapshot(
            focusedRole: "AXTextField",
            focusedTitle: "Search"
        )
    )
    expect(search.format == .searchQuery, "search fields should use search query formatting")

    let filePath = AppContextProfile.profile(
        bundleIdentifier: "com.apple.finder",
        localizedName: "Finder",
        screenContext: ScreenContextSnapshot(
            focusedRole: "AXTextField",
            selectedTextSnippet: "/Users/tiko/Documents/My wiki/index.md"
        )
    )
    expect(filePath.format == .filePath, "file path snippets should use file path formatting")

    let documentText = AppContextProfile.profile(
        bundleIdentifier: "com.apple.TextEdit",
        localizedName: "TextEdit",
        screenContext: ScreenContextSnapshot(
            focusedRole: "AXTextArea",
            selectedTextSnippet: "Текущий абзац"
        )
    )
    expect(documentText.format == .documentText, "text areas with context should use document text formatting")
    expect(documentText.screenContext?.selectedTextSnippet == "Текущий абзац", "non-sensitive snippets may be retained")
}

func testContextAwareDestinationFormatting() async throws {
    let search = try await RulePolisher(
        context: AppContextProfile(
            format: .searchQuery,
            displayName: "Safari",
            screenContext: ScreenContextSnapshot(focusedTitle: "Search")
        )
    ).polish("как приготовить фильтр кофе точка")
    expect(search == "как приготовить фильтр кофе", "search query should stay literal without final punctuation, got: \(search)")

    let url = try await RulePolisher(
        context: AppContextProfile(
            format: .url,
            displayName: "Safari",
            screenContext: ScreenContextSnapshot(focusedTitle: "Address")
        )
    ).polish("https двоеточие слеш слеш example dot com slash docs")
    expect(url == "https://example.com/docs", "spoken URL should become URL literal, got: \(url)")

    let filePath = try await RulePolisher(
        context: AppContextProfile(format: .filePath, displayName: "Finder")
    ).polish("слеш Users слеш tiko слеш Documents слеш My wiki")
    expect(filePath == "/Users/tiko/Documents/My wiki", "spoken file path should become path literal, got: \(filePath)")

    let shortChat = try await RulePolisher(
        context: AppContextProfile(format: .chatMessage, displayName: "Slack")
    ).polish("sounds good точка")
    expect(shortChat == "sounds good", "short chat message should not force a trailing period, got: \(shortChat)")
}

func testContextAwareInsertionUsesNearbyText() async throws {
    let midSentence = try await RulePolisher(
        context: AppContextProfile(
            format: .documentText,
            displayName: "TextEdit",
            screenContext: ScreenContextSnapshot(
                focusedRole: "AXTextArea",
                textBeforeCursorSnippet: "Я думаю, что",
                textAfterCursorSnippet: " завтра будет поздно."
            )
        )
    ).polish("Это хорошая идея точка")
    expect(midSentence == " это хорошая идея", "mid-sentence insertion should lowercase first word, add leading space, and avoid duplicate punctuation, got: \(midSentence)")

    let beforePunctuation = try await RulePolisher(
        context: AppContextProfile(
            format: .documentText,
            displayName: "TextEdit",
            screenContext: ScreenContextSnapshot(
                focusedRole: "AXTextArea",
                textBeforeCursorSnippet: "Plan",
                textAfterCursorSnippet: ", then ship"
            )
        )
    ).polish("готов точка")
    expect(beforePunctuation == " готов", "insertion before punctuation should drop final punctuation, got: \(beforePunctuation)")

    let replacingSelection = try await RulePolisher(
        context: AppContextProfile(
            format: .documentText,
            displayName: "TextEdit",
            screenContext: ScreenContextSnapshot(
                focusedRole: "AXTextArea",
                selectedTextSnippet: "старый текст",
                textBeforeCursorSnippet: "До ",
                textAfterCursorSnippet: " после"
            )
        )
    ).polish("новый текст точка")
    expect(replacingSelection == "Новый текст.", "selection replacement should stay standalone, got: \(replacingSelection)")
}

func testLocalContextHintsPreserveVisibleProperNouns() async throws {
    let polished = try await RulePolisher(
        context: AppContextProfile(
            format: .documentText,
            displayName: "Notes",
            screenContext: ScreenContextSnapshot(
                focusedRole: "AXTextArea",
                clipboardTextSnippet: "Project Zephyr roadmap"
            )
        )
    ).polish("project zephyr is ready")

    expect(polished == "Project Zephyr is ready.", "context proper noun casing should be preserved, got: \(polished)")
}

func testRulePolisherUsesTargetAppContext() async throws {
    let email = try await RulePolisher(
        context: AppContextProfile(format: .email, displayName: "Mail")
    ).polish("привет команда новая строка отправляю короткий отчёт точка спасибо")
    expect(email == "Привет, команда!\n\nОтправляю короткий отчёт.\n\nСпасибо.", "email context should format a short message, got: \(email)")

    let terminal = try await RulePolisher(
        context: AppContextProfile(format: .terminalCommand, displayName: "Terminal")
    ).polish("git status")
    expect(terminal == "git status", "terminal context should not capitalize commands, got: \(terminal)")

    let chat = try await RulePolisher(
        context: AppContextProfile(format: .chatMessage, displayName: "Telegram")
    ).polish("привет точка я на месте точка")
    expect(chat == "Привет. Я на месте.", "chat context should stay compact, got: \(chat)")
}

func testRulePolisherKeepsSensitiveContextLiteral() async throws {
    let password = try await RulePolisher(
        context: AppContextProfile(format: .password, displayName: "Safari")
    ).polish("my secret password dot one")
    expect(password == "my secret password dot one", "password context should not alter literal text, got: \(password)")

    let url = try await RulePolisher(
        context: AppContextProfile(format: .url, displayName: "Safari")
    ).polish("example dot com slash docs")
    expect(url == "example.com/docs", "url context should normalize spoken URL without sentence punctuation, got: \(url)")

    let filePath = try await RulePolisher(
        context: AppContextProfile(format: .filePath, displayName: "Finder")
    ).polish("/Users/tiko/Documents/My wiki/index.md")
    expect(filePath == "/Users/tiko/Documents/My wiki/index.md", "file path context should stay literal, got: \(filePath)")
}

// MARK: - UsageStatsStore

private func makeUsageStore(calendar: Calendar = .current) throws -> (UsageStatsStore, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (try UsageStatsStore(directory: directory, calendar: calendar), directory)
}

func testUsageStatsLifetimeIgnoresRetentionWindow() throws {
    let (store, dir) = try makeUsageStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    // Старая запись (90 дней назад) и свежая — обе должны попасть в lifetime.
    let old = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
    try store.recordDictation(wordCount: 10, durationSeconds: 12, modelID: "turbo", at: old)
    try store.recordDictation(wordCount: 5, durationSeconds: 4, modelID: "turbo", at: Date())

    let life = try store.lifetimeSummary()
    expect(life.dictationCount == 2, "lifetime counts all events regardless of age")
    expect(life.wordCount == 15, "lifetime sums words")
    expect(life.durationSeconds == 16, "lifetime sums duration")
}

func testUsageStatsPeriodSlices() throws {
    let (store, dir) = try makeUsageStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let now = Date()
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    // сегодня x2, 3 дня назад x1, 20 дней назад x1
    try store.recordDictation(wordCount: 3, durationSeconds: 2, modelID: "turbo", at: today.addingTimeInterval(3600))
    try store.recordDictation(wordCount: 4, durationSeconds: 3, modelID: "turbo", at: today.addingTimeInterval(7200))
    try store.recordDictation(wordCount: 6, durationSeconds: 5, modelID: "turbo", at: cal.date(byAdding: .day, value: -3, to: today)!.addingTimeInterval(3600))
    try store.recordDictation(wordCount: 9, durationSeconds: 8, modelID: "turbo", at: cal.date(byAdding: .day, value: -20, to: today)!.addingTimeInterval(3600))

    let day = try store.stats(for: .day, now: now)
    expect(day.dictationCount == 2, "day period counts only today, got \(day.dictationCount)")
    expect(day.wordCount == 7, "day words")
    expect(day.daily.count == 1, "day has 1 bucket")

    let week = try store.stats(for: .week, now: now)
    expect(week.dictationCount == 3, "week counts today + 3 days ago, got \(week.dictationCount)")
    expect(week.activeDays == 2, "week active days")
    expect(week.daily.count == 7, "week has 7 zero-filled buckets")

    let month = try store.stats(for: .month, now: now)
    expect(month.dictationCount == 4, "month counts all four, got \(month.dictationCount)")
    expect(month.activeDays == 3, "month active days")
    expect(month.daily.count == 30, "month has 30 buckets")
    expect(month.wordCount == 22, "month words")
}

func testUsageStatsStreakAndSessions() throws {
    let (store, dir) = try makeUsageStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    // подряд: сегодня, вчера, позавчера — стрик 3; затем пропуск, потом 5 дней назад
    for offset in [0, 1, 2, 5] {
        try store.recordDictation(wordCount: 2, durationSeconds: 1, modelID: "turbo", at: cal.date(byAdding: .day, value: -offset, to: today)!.addingTimeInterval(3600))
    }
    let streak = try store.currentStreak()
    expect(streak == 3, "streak should be 3 consecutive days, got \(streak)")

    // Исторический максимум (B8 «Longest streak»): прошлый стрик из 3 дней (offsets 0,1,2)
    // длиннее одиночного дня 5 дней назад, поэтому остаётся равным текущему.
    let longest = try store.longestStreak()
    expect(longest == 3, "longest streak should be 3, got \(longest)")

    try store.recordSession()
    try store.recordSession()
    let week = try store.stats(for: .week)
    expect(week.sessionCount == 2, "two sessions recorded in week, got \(week.sessionCount)")
}

func testUsageStatsBackfillsFromHistoryOnce() throws {
    let (store, dir) = try makeUsageStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let entries = [
        DictationEntry(modelID: "turbo", durationSeconds: 3, processingSeconds: 1, text: "одно два три"),
        DictationEntry(modelID: "turbo", durationSeconds: 5, processingSeconds: 1, text: "четыре пять")
    ]
    let imported = try store.backfillIfEmpty(from: entries)
    expect(imported == 2, "first backfill imports all entries")

    let again = try store.backfillIfEmpty(from: entries)
    expect(again == 0, "second backfill is a no-op when events exist")

    let life = try store.lifetimeSummary()
    expect(life.dictationCount == 2, "backfilled dictation count")
    expect(life.wordCount == 5, "backfilled word count (3 + 2)")
}

func testUsageStatsDashboardSnapshotIncludesLifetimePeriodsAndStreak() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let (store, dir) = try makeUsageStore(calendar: calendar)
    defer { try? FileManager.default.removeItem(at: dir) }

    let now = Date(timeIntervalSince1970: 1_717_545_600) // 2024-06-05 00:00:00 UTC
    let today = calendar.startOfDay(for: now)
    try store.recordDictation(wordCount: 4, durationSeconds: 2, modelID: "turbo", at: today.addingTimeInterval(3600))
    try store.recordDictation(wordCount: 6, durationSeconds: 3, modelID: "turbo", at: calendar.date(byAdding: .day, value: -1, to: today)!.addingTimeInterval(3600))
    try store.recordDictation(wordCount: 8, durationSeconds: 4, modelID: "turbo", at: calendar.date(byAdding: .day, value: -20, to: today)!.addingTimeInterval(3600))
    try store.recordSession(at: today.addingTimeInterval(1800))

    let snapshot = try store.dashboardSnapshot(now: now)

    expect(snapshot.lifetime.dictationCount == 3, "dashboard lifetime should include all dictations")
    expect(snapshot.stats(for: .day).dictationCount == 1, "day snapshot should count today only")
    expect(snapshot.stats(for: .week).dictationCount == 2, "week snapshot should count today and yesterday")
    expect(snapshot.stats(for: .month).dictationCount == 3, "month snapshot should include older event")
    expect(snapshot.stats(for: .week).sessionCount == 1, "snapshot should include session count")
    expect(snapshot.currentStreak == 2, "snapshot should expose current streak")
    expect(snapshot.longestStreak == 2, "snapshot should expose longest streak")
}

do {
    testBuiltInProfilesExposeTurboAndLargeV3()
    testFindProfileByIdentifier()
    testNormalizesWhitespaceWithoutChangingMeaning()
    testKeepsIntentionalParagraphBreaks()
    testFormatsLongDictationIntoParagraphs()
    testAddsParagraphsOnSemanticTransitions()
    testKeepsShortDictationAsSingleParagraph()
    testStrongMarkerStartsNewParagraph()
    testSplitsVeryLongWallOfText()
    testLocalLLMModelDefaults()
    try await testLocalLLMPolisherFallsBackToRulesWhenServerUnavailable()
    testRemovesSubtitleHallucinationTail()
    testRemovesEditorSubtitleCredits()
    testNormalizesWhisperSegmentNewlines()
    try testAppendAndReadHistoryEntriesNewestFirst()
    try testHistoryDeleteAndClear()
    try testRecentRespectsLimit()
    try testHistorySearch()
    testWhisperCommandBuildsCLIArguments()
    try testDefaultSettingsUseLocalFreeModel()
    testLegacyInstructionPromptMigratesToGlossary()
    testSmartContextMigratesLegacyContextToggles()
    testSpokenLanguagesMigrationAndEffective()
    testAutomaticInterfaceLanguageResolvesFromPreferredLanguages()
    testInterfaceLanguageNamesIncludeAutomaticMode()
    try testSettingsMigratesLegacyHotkeyToToggleAndKeepsHoldFn()
    try testSettingsDetectsDuplicateDictationHotkeys()
    try testMediaInterruptionModePersistsAndMigratesFromPauseToggle()
    testAppBrandUsesLyraVoiceName()
    testAppBrandDeclaresLogoAssets()
    testFunctionKeyHotkeyDisplaysAsFn()
    testModifierOnlyKeyCodesAreNotCapturableHotkeys()
    testDictationUsageSummaryCountsWordsAndDuration()
    try testUsageStatsLifetimeIgnoresRetentionWindow()
    try testUsageStatsPeriodSlices()
    try testUsageStatsStreakAndSessions()
    try testUsageStatsBackfillsFromHistoryOnce()
    try testUsageStatsDashboardSnapshotIncludesLifetimePeriodsAndStreak()
    try testSettingsStoreSavesAndLoadsSettings()
    try testSettingsDecodeFallsBackFromModifierOnlyHotkey()
    try testProcessRunnerReturnsStandardOutput()
    try testProcessRunnerHandlesLargeOutputWithoutDeadlock()
    try testWhisperCLITranscriberUsesCommandOutput()
    try await testVoiceCommandsAndFillersAndDictionary()
    testCorrectionCommands()
    try await testQuoteVoiceCommands()
    testControlPanelStateExposesExpectedActions()
    testControlPanelNavigationMatchesReferenceIA()
    try testHomeDashboardDoesNotDuplicatePrimaryUsageMetrics()
    try testControlPanelUsesRestrainedReferenceShell()
    try testRecordingOverlayWaveformIsVisiblyResponsive()
    try testAppDelegateObservesSystemLocaleOnlyForAutomaticInterfaceLanguage()
    try testAppDelegateDoesNotPersistSensitiveContext()
    testRemovesServiceTagsAndConsecutiveDuplicates()
    testModelProfilesExposeInterfaceCopy()
    testOverlayMetricsStayCompact()
    try testDictionaryEditorKeepsInputAboveSeparatedEntries()
    try testMicrophonePermissionErrorUsesTransientOverlay()
    try testAudioRecorderKeepsLegacyFallback()
    try testDictationPipelineWritesDiagnostics()
    try testAudioSettingsExposeMediaModeSelector()
    try testControlButtonRadiiStayModerate()
    try testMicrophonePermissionUsesAudioRecordingAPI()
    try testDevAppSigningIncludesMicrophoneEntitlement()
    testTargetAppContextProfiles()
    testScreenContextRefinesTargetFormat()
    try await testContextAwareDestinationFormatting()
    try await testContextAwareInsertionUsesNearbyText()
    try await testLocalContextHintsPreserveVisibleProperNouns()
    try await testRulePolisherUsesTargetAppContext()
    try await testRulePolisherKeepsSensitiveContextLiteral()
    try await testBuiltInVocabularyUsesCanonicalProductNames()
    try await testBuiltInVocabularyDisambiguatesClaudeCloudAndICloud()
    try await testUserDictionaryOverridesBuiltInVocabulary()
    try await testExplicitNumberedListFormatting()
    try await testOrdinalMarkersBecomeNumberedList()
    try await testHyphenDashAndPlaceVocabularyFormatting()
    try await testDatesAndMoneyAreNormalizedConservatively()
    print("LyraVoiceCoreSmokeTests passed")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
