import AppKit
import LyraVoiceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusBarMenu: NSMenu?
    private var launchAtLoginMenuItem: NSMenuItem?
    private var showInDockMenuItem: NSMenuItem?
    private var playSoundsMenuItem: NSMenuItem?
    private let overlayController = OverlayController()
    private let resultCardController = ResultCardController()
    private let mediaController = MediaController()
    private let localLLMServer = LocalLLMServer()
    private let audioRecorder = AudioRecorder()
    private let streamingASRService = StreamingASRService.shared
    private let clipboardPasteService = ClipboardPasteService()
    private let screenContextReader = ScreenContextReader()
    private let feedbackSoundPlayer = FeedbackSoundPlayer()
    private var settingsStore: SettingsStore?
    private var settings = AppSettings.defaultSettings()
    private var historyStore: HistoryStore?
    private var usageStatsStore: UsageStatsStore?
    private var recordingTimer: Timer?
    /// Последняя показанная целая секунда записи — чтобы обновлять control panel раз в секунду.
    private var lastRecordedSecond = 0
    private var appLocalShortcutMonitor: Any?
    private var appGlobalShortcutMonitor: Any?
    private var localShortcutMonitor: Any?
    private var globalShortcutMonitor: Any?
    private var isDownloadingModel = false
    private var downloadStatus = ""
    /// Последний показанный процент — чтобы не дёргать UI на каждый чанк (тысячи
    /// раз в секунду): прогресс обновляем только при смене целого процента.
    private var lastReportedPercent = -1
    private var controlPanelWindowController: ControlPanelWindowController?
    private var historyWindowController: HistoryWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var controlPanelState: ControlPanelState = .idle
    private var dictationTargetApp: NSRunningApplication?
    private var overlayDismissWorkItem: DispatchWorkItem?
    private var functionHotkeyIsDown = false
    private var lastFunctionToggleDate: Date?
    // Состояние «тапа» одиночного модификатора (Option/Control) для хоткея «Промпт для ИИ».
    private var aiPromptModifierArmed = false
    private var aiPromptModifierClean = false
    private var aiPromptModifierDownTime: Date?
    /// Текущая запись запущена через хоткей «Промпт для ИИ» — следующая транскрипция
    /// принудительно использует формат `.aiPrompt`, независимо от Smart Context.
    /// Сбрасывается сразу после прочтения в `transcribe`.
    private var activeRecordingAIPromptOverride = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStorage()
        applyBehaviorSettings()
        DiagnosticsLog.write("launch app=\(AppBrand.displayName) executable=\(AppBrand.executableName) bundle=\(Bundle.main.bundleIdentifier ?? "unknown")")
        // Если выбрана локальная LLM-полировка и модель скачана — заранее
        // прогреваем llama-server, чтобы первая диктовка не ждала загрузку модели.
        localLLMServer.ensureRunning(for: settings)
        startWhisperServerIfPossible()
        overlayController.delegate = self
        overlayController.displayMode = settings.overlayDisplayMode
        resultCardController.onCopy = { [weak self] text in
            self?.clipboardPasteService.copy(text)
        }
        configureMenuBar()
        startSystemLocaleObserver()
        startAppShortcutMonitors()
        // Accessibility-доступ нужен для глобального хоткея и авто-вставки, но
        // НЕ дёргаем системный промпт на старте — это раздражает. Статус
        // показываем в панели, а запрос инициирует пользователь кнопкой.
        let forceOnboarding = ProcessInfo.processInfo.environment["LYRA_ONBOARDING_PREVIEW"] != nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if forceOnboarding || !self.settings.hasCompletedOnboarding {
                self.showOnboarding()
            } else {
                self.showControlPanel()
            }
        }

        // Превью оверлея для дизайн-проверки:
        // LYRA_OVERLAY_PREVIEW=idle|toggle|ptt|processing|streaming|cycle
        // либо CLI: open -n App --args --overlay-preview streaming (env не проходит через open).
        if let preview = overlayPreviewMode() {
            overlayController.presentationMode = preview == "ptt" ? .pushToTalk : .toggle
            overlayController.displayMode = .streaming   // превью игнорирует пользовательскую настройку
            runOverlayPreview(preview)
        }
    }

    /// Режим превью оверлея из env или CLI-аргумента `--overlay-preview <mode>`.
    private func overlayPreviewMode() -> String? {
        if let env = ProcessInfo.processInfo.environment["LYRA_OVERLAY_PREVIEW"] { return env }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--overlay-preview"), i + 1 < args.count { return args[i + 1] }
        return nil
    }

    /// Дизайн-превью состояний оверлея (только при LYRA_OVERLAY_PREVIEW).
    private func runOverlayPreview(_ preview: String) {
        let sampleText = "Это пример живого текста, который растёт в стриминг-панель по мере распознавания речи."
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self else { return }
            switch preview {
            case "processing":
                self.overlayController.show(state: .processing(modelName: "turbo"))
            case "streaming":
                self.overlayController.show(state: .streaming(text: sampleText, targetApp: "Code", micName: "MacBook"))
            case "idle":
                self.overlayController.show(state: .recording(seconds: 3, level: 0.0))
            case "cycle":
                // Демонстрация A.3 compact→grow и A.4 bloom: pill → панель → обработка → повтор.
                while !Task.isCancelled {
                    self.overlayController.show(state: .recording(seconds: 0, level: 0.6))
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    self.overlayController.show(state: .streaming(text: sampleText, targetApp: "Code", micName: "MacBook"))
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    self.overlayController.show(state: .processing(modelName: "turbo"))
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            default:
                self.overlayController.show(state: .recording(seconds: 3, level: 0.7))
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlPanel()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        localLLMServer.stop()
        WhisperServerService.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Запустить whisper-server фоново. Пропускаем если выбран облачный провайдер.
    private func startWhisperServerIfPossible() {
        let currentSettings = settings
        guard currentSettings.transcriptionProvider == .local else {
            WhisperServerService.shared.stop()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let modelURL = try? currentSettings.modelURL() else { return }
            WhisperServerService.shared.startIfNeeded(
                modelURL: modelURL,
                threads: WhisperCommand.recommendedThreadCount,
                beamSize: 5,
                suppressNonSpeech: true
            )
        }
    }

    private func configureStorage() {
        do {
            let supportRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
            let directory = supportRoot.appendingPathComponent(AppBrand.applicationSupportDirectoryName, isDirectory: true)
            let didMigrate = migrateLegacyStorageIfNeeded(into: directory, root: supportRoot)

            historyStore = try HistoryStore(directory: directory)
            // Накопительная статистика дашборда — отдельно от истории, не урезается
            // по retention. Бэкфилл из истории при первом запуске после внедрения,
            // плюс запись текущей сессии для счётчика активности.
            do {
                let statsStore = try UsageStatsStore(directory: directory)
                if let history = historyStore {
                    let imported = try statsStore.backfillIfEmpty(from: history.all())
                    if imported > 0 { DiagnosticsLog.write("usage stats backfilled events=\(imported)") }
                }
                try? statsStore.recordSession()
                usageStatsStore = statsStore
            } catch {
                DiagnosticsLog.write("usage stats unavailable error=\(error.localizedDescription)")
            }
            let settingsStore = try SettingsStore(directory: directory)
            self.settingsStore = settingsStore
            settings = try settingsStore.load()

            if didMigrate {
                // Перенесённый settings.json хранит абсолютный путь к моделям со
                // старым именем папки — чиним, чтобы скачанная модель не «потерялась».
                if settings.modelDirectoryPath.contains("/WhisperKey/") {
                    settings.modelDirectoryPath = settings.modelDirectoryPath
                        .replacingOccurrences(of: "/WhisperKey/", with: "/\(AppBrand.applicationSupportDirectoryName)/")
                }
                // Bundle id сменился вместе с именем продукта → системные права на
                // микрофон/Accessibility сбросились. Прогоняем онбординг заново,
                // чтобы он перевыдал доступ под новым идентификатором.
                settings.hasCompletedOnboarding = false
                try? settingsStore.save(settings)
                DiagnosticsLog.write("storage migrated from legacy WhisperKey directory")
            }

            applyInterfaceLanguageFromSettings()
            DiagnosticsLog.isEnabled = settings.diagnosticsLoggingEnabled
            if settings.saveRecordings {
                RecordingArchive.pruneOldRecordings(retention: settings.recordingsRetention)
            }
            DiagnosticsLog.write("storage configured directory=\(directory.path) model=\(settings.selectedModelID) toggleHotkey=\(settings.toggleHotkey.displayText) holdHotkey=\(settings.pushToTalkHotkey.displayText) deviceUID=\(settings.inputDeviceUID.isEmpty ? "default" : settings.inputDeviceUID)")
        } catch {
            DiagnosticsLog.write("storage failed error=\(error.localizedDescription)")
            showTransientError(controlMessage: "History unavailable: \(error.localizedDescription)")
        }
    }

    /// Одноразовый перенос данных со старого имени продукта (WhisperKey) на новое
    /// (Lyra Voice): переносим всю папку целиком, чтобы скачанные модели, settings.json
    /// и история сохранились. Возвращает true, если миграция действительно произошла.
    private func migrateLegacyStorageIfNeeded(into directory: URL, root: URL) -> Bool {
        let fm = FileManager.default
        let legacy = root.appendingPathComponent("WhisperKey", isDirectory: true)
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: directory.path) else { return false }
        do {
            try fm.moveItem(at: legacy, to: directory)
            return true
        } catch {
            DiagnosticsLog.write("legacy storage migration failed error=\(error.localizedDescription)")
            return false
        }
    }

    /// Применяет «поведенческие» настройки (группа F) к системе: видимость в Dock,
    /// звуки диктовки и автозапуск. Автозапуск сверяем с фактическим статусом
    /// `SMAppService` и подгоняем настройку под реальность, чтобы UI не врал.
    private func applyBehaviorSettings() {
        applyActivationPolicy()
        feedbackSoundPlayer.isEnabled = settings.playFeedbackSounds

        let actualLoginItem = LoginItemService.isEnabled
        if settings.launchAtLogin != actualLoginItem {
            // Намерение пользователя != фактическое состояние: пробуем привести
            // систему к настройке; если не вышло — фиксируем фактическое.
            let result = LoginItemService.setEnabled(settings.launchAtLogin)
            if result != settings.launchAtLogin {
                settings.launchAtLogin = result
                try? settingsStore?.save(settings)
            }
        }
    }

    /// `.regular` (иконка в Dock) или `.accessory` (только строка меню) — по настройке.
    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
    }

    private func configureMenuBar() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let logo = BrandAssets.logoImage(size: 18) {
            item.button?.image = logo
            item.button?.imagePosition = .imageLeading
            item.button?.title = ""
        } else {
            item.button?.title = AppBrand.menuBarTitle
        }
        item.button?.toolTip = AppBrand.displayName

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: L.t("Открыть \(AppBrand.displayName)", "Open \(AppBrand.displayName)"),
            action: #selector(showControlPanel),
            keyEquivalent: "o"
        ))
        menu.addItem(NSMenuItem(
            title: L.t("Настройка заново…", "Set up again…"),
            action: #selector(showOnboarding),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(
            title: L.t("Запускать при входе в систему", "Launch at login"),
            action: #selector(toggleLaunchAtLoginFromMenu),
            keyEquivalent: ""
        )
        menu.addItem(launchItem)
        launchAtLoginMenuItem = launchItem

        let dockItem = NSMenuItem(
            title: L.t("Показывать в Dock", "Show in Dock"),
            action: #selector(toggleShowInDockFromMenu),
            keyEquivalent: ""
        )
        menu.addItem(dockItem)
        showInDockMenuItem = dockItem

        let soundItem = NSMenuItem(
            title: L.t("Звук уведомления", "Notification sound"),
            action: #selector(togglePlaySoundsFromMenu),
            keyEquivalent: ""
        )
        menu.addItem(soundItem)
        playSoundsMenuItem = soundItem

        menu.addItem(NSMenuItem.separator())
#if DEBUG
        menu.addItem(NSMenuItem(
            title: "Show Recording Overlay",
            action: #selector(showRecordingOverlay),
            keyEquivalent: "r"
        ))
        menu.addItem(NSMenuItem(
            title: "Show Processing Overlay",
            action: #selector(showProcessingOverlay),
            keyEquivalent: "p"
        ))
        menu.addItem(NSMenuItem(
            title: "Transcribe Test Audio",
            action: #selector(transcribeTestAudio),
            keyEquivalent: "t"
        ))
        menu.addItem(NSMenuItem(
            title: "Copy Last Dictation",
            action: #selector(copyLastDictation),
            keyEquivalent: "c"
        ))
        menu.addItem(NSMenuItem(
            title: "Open History File",
            action: #selector(openHistoryFile),
            keyEquivalent: "h"
        ))
        menu.addItem(NSMenuItem(
            title: "Open Microphone Settings",
            action: #selector(openMicrophoneSettings),
            keyEquivalent: "m"
        ))
        menu.addItem(NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: "a"
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Start Recording",
            action: #selector(startRecording),
            keyEquivalent: "s"
        ))
        menu.addItem(NSMenuItem(
            title: "Stop and Transcribe",
            action: #selector(stopAndTranscribeRecording),
            keyEquivalent: "d"
        ))
        menu.addItem(NSMenuItem.separator())
#endif
        menu.addItem(NSMenuItem(
            title: "Quit \(AppBrand.displayName)",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        menu.items.forEach { $0.target = self }
        menu.delegate = self
        refreshBehaviorMenuState()

        // Левый клик = toggle запись. Правый клик = меню.
        statusBarMenu = menu
        item.button?.target = self
        item.button?.action = #selector(statusBarButtonClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    private func startSystemLocaleObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemLocaleDidChange(_:)),
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )
    }

    @objc private func systemLocaleDidChange(_ notification: Notification) {
        guard settings.interfaceLanguage == AppSettings.automaticInterfaceLanguage else { return }
        let previousLanguage = L.current.rawValue
        applyInterfaceLanguageFromSettings()
        guard L.current.rawValue != previousLanguage else { return }
        rebuildLocalizedInterface()
    }

    private func applyInterfaceLanguageFromSettings() {
        L.set(AppSettings.resolvedInterfaceLanguage(settings.interfaceLanguage))
    }

    private func rebuildLocalizedInterface() {
        let controlPanelWasVisible = controlPanelWindowController?.window?.isVisible ?? false
        let historyWasVisible = historyWindowController?.window?.isVisible ?? false
        let onboardingWasVisible = onboardingWindowController?.window?.isVisible ?? false

        configureMenuBar()

        controlPanelWindowController?.close()
        controlPanelWindowController = nil
        historyWindowController?.close()
        historyWindowController = nil
        onboardingWindowController?.close()
        onboardingWindowController = nil

        if controlPanelWasVisible {
            showControlPanel()
        }
        if historyWasVisible {
            openHistoryFile()
        }
        if onboardingWasVisible {
            showOnboarding()
        }
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusBarMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        } else {
            if audioRecorder.isRecording {
                stopAndTranscribeRecording()
            } else {
                startRecordingWithOverlayMode(.toggle)
            }
        }
    }

    /// Подтягивает галочки тумблеров поведения (группа F) под актуальные настройки —
    /// вызывается при сборке меню и перед каждым показом (`menuNeedsUpdate`).
    private func refreshBehaviorMenuState() {
        launchAtLoginMenuItem?.state = settings.launchAtLogin ? .on : .off
        showInDockMenuItem?.state = settings.showInDock ? .on : .off
        playSoundsMenuItem?.state = settings.playFeedbackSounds ? .on : .off
    }

    @objc private func toggleLaunchAtLoginFromMenu() {
        controlPanelDidSetLaunchAtLogin(!settings.launchAtLogin)
        refreshBehaviorMenuState()
    }

    @objc private func toggleShowInDockFromMenu() {
        controlPanelDidSetShowInDock(!settings.showInDock)
        refreshBehaviorMenuState()
    }

    @objc private func togglePlaySoundsFromMenu() {
        controlPanelDidSetPlaySounds(!settings.playFeedbackSounds)
        refreshBehaviorMenuState()
    }

    @objc private func showRecordingOverlay() {
        setControlPanelState(.recording(seconds: 0))
        overlayController.show(state: .recording(seconds: 0, level: 0.2))
    }

    @objc private func showProcessingOverlay() {
        let modelName = selectedProfile?.displayName ?? settings.selectedModelID
        setControlPanelState(.processing(modelName: modelName))
        overlayController.show(state: .processing(modelName: modelName))
    }

    @objc private func transcribeTestAudio() {
        // Облачный провайдер не требует локальной модели — проверяем файл только для .local.
        guard settings.transcriptionProvider == .openAI || validateSelectedModelInstalled() else { return }
        let modelName = settings.transcriptionProvider == .openAI
            ? settings.openAITranscriptionModel.displayName
            : (selectedProfile?.displayName ?? settings.selectedModelID)
        setControlPanelState(.processing(modelName: modelName))
        overlayController.show(state: .processing(modelName: modelName))

        Task.detached {
            do {
                let currentSettings = await MainActor.run { self.settings }
                let audioURL = try await MainActor.run { try self.testAudioURL() }

                let text: String
                if currentSettings.transcriptionProvider == .openAI {
                    text = try CloudTranscriptionService.transcribe(
                        audioURL: audioURL,
                        apiKey: currentSettings.openAIAPIKey,
                        model: currentSettings.openAITranscriptionModel,
                        language: currentSettings.effectiveTranscriptionLanguage
                    )
                } else {
                    let command = WhisperCommand(
                        binaryURL: URL(fileURLWithPath: EngineLocator.path(for: "whisper-cli", fallback: currentSettings.whisperBinaryPath)),
                        modelURL: try currentSettings.modelURL(),
                        audioURL: audioURL,
                        language: currentSettings.effectiveTranscriptionLanguage,
                        initialPrompt: currentSettings.initialPrompt,
                        vadEnabled: currentSettings.vadEnabled,
                        vadModelURL: currentSettings.vadModelURL()
                    )
                    text = try WhisperCLITranscriber().transcribe(command: command, timeoutSeconds: 120)
                }

                await MainActor.run {
                    self.clipboardPasteService.copy(text)
                    self.setControlPanelState(.copied)
                    self.overlayController.show(state: .copied)
                    self.scheduleOverlayDismiss(after: 2.0)
                }
            } catch {
                await MainActor.run {
                    self.setControlPanelState(.error(error.localizedDescription))
                    self.overlayController.show(state: .error(error.localizedDescription))
                    self.scheduleOverlayDismiss(after: 3.0)
                }
            }
        }
    }

    @objc private func startRecording() {
        startRecordingWithOverlayMode(.toggle)
    }

    private func startRecordingWithOverlayMode(_ presentationMode: OverlayPresentationMode) {
        DiagnosticsLog.write("startRecording requested state=\(controlPanelState.statusTitle) isRecording=\(audioRecorder.isRecording) toggleHotkey=\(settings.toggleHotkey.displayText) holdHotkey=\(settings.pushToTalkHotkey.displayText) overlayMode=\(presentationMode) deviceUID=\(settings.inputDeviceUID.isEmpty ? "default" : settings.inputDeviceUID) micStatus=\(MicrophonePermission.statusDescription)")
        // Запоминаем приложение, в которое пользователь диктует, ещё до начала
        // записи — позже вернём в него фокус, чтобы Cmd+V попал по адресу.
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            dictationTargetApp = frontmost
        }
        cancelOverlayDismiss()
        overlayController.presentationMode = presentationMode
        Task {
            guard settings.transcriptionProvider == .openAI || validateSelectedModelInstalled() else { return }
            let hasMicrophoneAccess = await MicrophonePermission.requestIfNeeded()
            DiagnosticsLog.write("microphone permission result allowed=\(hasMicrophoneAccess) status=\(MicrophonePermission.statusDescription)")
            guard hasMicrophoneAccess else {
                showTransientError(controlMessage: "Microphone access is required. Open Settings.")
                return
            }

            do {
                let deviceUID = settings.inputDeviceUID.isEmpty ? nil : settings.inputDeviceUID
                let recordingURL = try audioRecorder.start(deviceUID: deviceUID)
                DiagnosticsLog.write("recording started backend=\(audioRecorder.activeBackendName) url=\(recordingURL.path)")
                mediaController.apply(settings.mediaInterruptionMode)
                feedbackSoundPlayer.playRecordingStarted()
                startRecordingTimer()
            } catch {
                DiagnosticsLog.write("recording start failed error=\(error.localizedDescription)")
                showTransientError(controlMessage: error.localizedDescription)
            }
        }
    }

    /// Порог silence-гейта по ПИКОВОМУ уровню (макс. оконный RMS) в dBFS: дропаем только
    /// если даже самый громкий момент записи тише этого порога — то есть настоящая тишина.
    /// Речь даёт пики ≈ −15…−30 dBFS, шумовой пол/тишина ≈ −50…−45. Порог −45 консервативен:
    /// любая реальная речь его проходит, поэтому надиктованный текст больше не теряется.
    private static let silenceGateDBFS: Double = -45

    @objc private func stopAndTranscribeRecording() {
        DiagnosticsLog.write("stopAndTranscribe requested isRecording=\(audioRecorder.isRecording) backend=\(audioRecorder.activeBackendName)")
        do {
            guard settings.transcriptionProvider == .openAI || validateSelectedModelInstalled() else { return }
            let recordedAudio = try audioRecorder.stop()
            DiagnosticsLog.write("recording stopped backend=\(recordedAudio.backendName) duration=\(String(format: "%.2f", recordedAudio.durationSeconds)) bytes=\(DiagnosticsLog.byteCountDescription(for: recordedAudio.url)) avgLevel=\(recordedAudio.speechLevelDBFS.map { String(format: "%.1f", $0) } ?? "nil") peakLevel=\(recordedAudio.peakSpeechLevelDBFS.map { String(format: "%.1f", $0) } ?? "nil") url=\(recordedAudio.url.path)")
            // Текст, уже распознанный стримингом, — главный признак, что речь БЫЛА.
            // Снимаем его ДО остановки таймера (stopRecordingTimer глушит streaming).
            let streamingTextAtStop = streamingASRService.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            mediaController.restoreIfNeeded()
            feedbackSoundPlayer.playRecordingStopped()
            stopRecordingTimer()

            // Silence-гейт: дропаем ТОЛЬКО настоящую тишину, чтобы whisper не галлюцинировал
            // («The next step is…», «Субтитры…»). Решаем по ПИКУ (макс. оконный уровень), а не
            // по среднему — иначе тихая/паузная речь ложно считалась тишиной и надиктованный
            // текст пропадал. Доп. предохранитель: если стриминг уже что-то распознал — речь
            // точно была, не дропаем ни при каких условиях.
            let peak = recordedAudio.peakSpeechLevelDBFS
            if streamingTextAtStop.isEmpty, let peak, peak < Self.silenceGateDBFS {
                DiagnosticsLog.write("silence gate: skipping transcription (peak=\(String(format: "%.1f", peak)) dBFS < \(Self.silenceGateDBFS), no streaming text)")
                try? FileManager.default.removeItem(at: recordedAudio.url)
                activeRecordingAIPromptOverride = false
                setControlPanelState(.idle)
                overlayController.hide()
                return
            }

            let modelName = selectedProfile?.displayName ?? settings.selectedModelID
            setControlPanelState(.processing(modelName: modelName))
            overlayController.show(state: .processing(modelName: modelName))
            transcribe(audioURL: recordedAudio.url, durationSeconds: recordedAudio.durationSeconds)
        } catch {
            DiagnosticsLog.write("stopAndTranscribe failed error=\(error.localizedDescription)")
            showTransientError(controlMessage: error.localizedDescription)
        }
    }

    private func cancelRecording() {
        do {
            if audioRecorder.isRecording {
                try audioRecorder.cancel()
                mediaController.restoreIfNeeded()
                feedbackSoundPlayer.playRecordingCancelled()
            }
            activeRecordingAIPromptOverride = false
            stopRecordingTimer()
            setControlPanelState(.idle)
            overlayController.hide()
        } catch {
            showTransientError(controlMessage: error.localizedDescription)
        }
    }

    private func startRecordingTimer() {
        stopRecordingTimer()
        startRecordingShortcutMonitors()
        lastRecordedSecond = 0
        setControlPanelState(.recording(seconds: 0))
        // В стриминг-режиме сразу показываем стриминг-панель (с «Слушаю»), а не обычный pill:
        // окно «распускается» из компактной формы в панель анимацией resize, без долгого
        // промежуточного pill и без ожидания первого чанка ASR (~1.5–3 с). Иначе — обычный pill.
        if shouldUseStreamingOverlay {
            let micName = AudioInputDevices.name(forUID: settings.inputDeviceUID)
            overlayController.show(state: .streaming(
                text: "",
                targetApp: dictationTargetApp?.localizedName,
                micName: micName
            ))
        } else {
            overlayController.show(state: .recording(seconds: 0, level: audioRecorder.normalizedPowerLevel))
        }
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Волну обновляем ЛЕГКО и часто (только уровень, без resize/reorder окна) —
                // это убирает рывки. Когда показана streaming-панель, метод сам no-op.
                self.overlayController.updateRecordingLevel(self.audioRecorder.normalizedPowerLevel)
                // Счётчик секунд в control panel — только при смене целой секунды:
                // его render() читает историю с диска и считать его 12×/сек дорого.
                let seconds = Int(self.audioRecorder.currentDuration.rounded(.down))
                if seconds != self.lastRecordedSecond {
                    self.lastRecordedSecond = seconds
                    self.setControlPanelState(.recording(seconds: seconds))
                }
            }
        }
        startStreamingASR()
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        stopRecordingShortcutMonitors()
        streamingASRService.stop()
    }

    /// Живой стриминг-оверлей доступен только при локальной транскрипции (warm whisper-server).
    private var shouldUseStreamingOverlay: Bool {
        settings.overlayDisplayMode == .streaming && settings.transcriptionProvider == .local
    }

    private func startStreamingASR() {
        guard shouldUseStreamingOverlay else { return }
        // Сервер мог уснуть по idle-таймауту — будим заранее; стриминг сам подхватит,
        // как только он поднимется (проверка готовности на каждом тике в StreamingASRService).
        if !WhisperServerService.shared.isRunning { startWhisperServerIfPossible() }
        let lang = settings.effectiveTranscriptionLanguage
        let prompt = settings.initialPrompt
        let targetAppName = dictationTargetApp?.localizedName
        let micUID = settings.inputDeviceUID
        streamingASRService.onTextUpdate = { [weak self] text in
            guard let self else { return }
            // Поздний in-flight чанк ASR может прилететь уже ПОСЛЕ остановки записи
            // (транскрипция одного окна занимает ~1.5 с, колбэк уже захвачен на фоновой
            // очереди). К этому моменту мы перешли в processing — не даём стриминг-панели
            // «вспыхнуть» поверх волны обработки. Гард по факту записи закрывает гонку.
            guard self.audioRecorder.isRecording else { return }
            // Склеиваем whisper-переносы и чистим кредит-галлюцинации, чтобы превью было
            // ровным (без разорванных слов и титров).
            let cleaned = TextPostProcessor.normalizeTranscriptNewlines(
                TextPostProcessor.stripHallucinations(text)
            )
            // Панель уже показана с момента старта — здесь только обновляем её текст
            // (пустой текст рисуется как «Слушаю...»).
            let micName = AudioInputDevices.name(forUID: micUID)
            self.overlayController.show(state: .streaming(text: cleaned, targetApp: targetAppName, micName: micName))
        }
        streamingASRService.start(recorder: audioRecorder, language: lang, prompt: prompt)
    }

    private func startRecordingShortcutMonitors() {
        stopRecordingShortcutMonitors()

        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.handleRecordingShortcut(event) == true else { return event }
            return nil
        }

        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                _ = self?.handleRecordingShortcut(event)
            }
        }
    }

    private func stopRecordingShortcutMonitors() {
        if let localShortcutMonitor {
            NSEvent.removeMonitor(localShortcutMonitor)
            self.localShortcutMonitor = nil
        }

        if let globalShortcutMonitor {
            NSEvent.removeMonitor(globalShortcutMonitor)
            self.globalShortcutMonitor = nil
        }
    }

    private func handleRecordingShortcut(_ event: NSEvent) -> Bool {
        guard audioRecorder.isRecording else { return false }

        switch event.keyCode {
        case 36, 76:
            stopAndTranscribeRecording()
            return true
        case 53:
            cancelRecording()
            return true
        default:
            return false
        }
    }

    private func startAppShortcutMonitors() {
        stopAppShortcutMonitors()

        appLocalShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard self?.handleAppShortcut(event) == true else { return event }
            return nil
        }

        appGlobalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            Task { @MainActor in
                _ = self?.handleAppShortcut(event)
            }
        }
    }

    private func stopAppShortcutMonitors() {
        if let appLocalShortcutMonitor {
            NSEvent.removeMonitor(appLocalShortcutMonitor)
            self.appLocalShortcutMonitor = nil
        }

        if let appGlobalShortcutMonitor {
            NSEvent.removeMonitor(appGlobalShortcutMonitor)
            self.appGlobalShortcutMonitor = nil
        }
    }

    private func handleAppShortcut(_ event: NSEvent) -> Bool {
        if handleAIPromptHotkey(event) {
            return true
        }
        if handleToggleHotkey(event) {
            return true
        }
        if handlePushToTalkHotkey(event) {
            return true
        }
        return false
    }

    /// Хоткей «Промпт для ИИ» (toggle-семантика): первое нажатие запускает запись с
    /// принудительным форматом `.aiPrompt`, повторное — останавливает и транскрибирует.
    /// Неназначенный хоткей (`isAssignable == false`) никогда не матчится.
    private func handleAIPromptHotkey(_ event: NSEvent) -> Bool {
        let hotkey = settings.aiPromptHotkey
        guard hotkey.isAssignable else { return false }

        // Одиночный модификатор (Option/Control) — срабатывание по «тапу»: нажал и отпустил
        // без других клавиш/модификаторов и быстро. Так Option-триггер не мешает обычному
        // использованию Option (Option+буква для символа, Ctrl+Option для PTT — «грязно»).
        if Hotkey.isModifierOnlyKeyCode(hotkey.keyCode), let modifierName = hotkey.modifierFlags.first {
            return handleSoloModifierAIPrompt(event, modifierName: modifierName)
        }

        guard event.type == .keyDown, event.matches(hotkey) else { return false }
        triggerAIPromptToggle()
        return true
    }

    private func triggerAIPromptToggle() {
        if audioRecorder.isRecording {
            stopAndTranscribeRecording()
        } else if controlPanelState.canStartRecording {
            activeRecordingAIPromptOverride = true
            startRecordingWithOverlayMode(.toggle)
        }
    }

    /// Детектор «тапа» одиночного модификатора для AI-Prompt. Срабатывает только если
    /// модификатор нажат и отпущен быстро, БЕЗ обычных клавиш и БЕЗ других модификаторов
    /// в этот момент — иначе это часть комбо/печати, игнорируем.
    private func handleSoloModifierAIPrompt(_ event: NSEvent, modifierName: String) -> Bool {
        let flag: NSEvent.ModifierFlags
        switch modifierName {
        case "option": flag = .option
        case "control": flag = .control
        case "command": flag = .command
        case "shift": flag = .shift
        default: return false
        }
        let allFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
        let otherFlags = allFlags.subtracting(flag)

        if event.type == .keyDown {
            // Обычная клавиша во время удержания модификатора → это комбо, не одиночный тап.
            aiPromptModifierClean = false
            return false
        }
        guard event.type == .flagsChanged else { return false }

        let isOurDown = event.modifierFlags.contains(flag)
        let hasOthers = !event.modifierFlags.intersection(otherFlags).isEmpty

        if isOurDown {
            if !aiPromptModifierArmed {
                aiPromptModifierArmed = true
                aiPromptModifierClean = !hasOthers
                aiPromptModifierDownTime = Date()
            } else if hasOthers {
                aiPromptModifierClean = false
            }
            return false
        }

        // Модификатор отпущен.
        if aiPromptModifierArmed {
            aiPromptModifierArmed = false
            let quick = aiPromptModifierDownTime.map { Date().timeIntervalSince($0) < 0.6 } ?? false
            let wasClean = aiPromptModifierClean
            aiPromptModifierClean = false
            aiPromptModifierDownTime = nil
            if wasClean, quick, !hasOthers {
                triggerAIPromptToggle()
                return true
            }
        }
        return false
    }

    private func handleToggleHotkey(_ event: NSEvent) -> Bool {
        if settings.toggleHotkey == .fn {
            return handleFunctionToggleHotkey(event)
        }

        guard event.type == .keyDown, event.matches(settings.toggleHotkey) else { return false }
        if audioRecorder.isRecording {
            stopAndTranscribeRecording()
        } else if controlPanelState.canStartRecording {
            startRecordingWithOverlayMode(.toggle)
        }
        return true
    }

    private func handlePushToTalkHotkey(_ event: NSEvent) -> Bool {
        if settings.pushToTalkHotkey == .fn {
            return handleFunctionPushToTalkHotkey(event)
        }

        if event.type == .keyDown, event.matches(settings.pushToTalkHotkey) {
            if !audioRecorder.isRecording, controlPanelState.canStartRecording {
                startRecordingWithOverlayMode(.pushToTalk)
            }
            return true
        }
        if event.type == .keyUp, UInt16(event.keyCode) == settings.pushToTalkHotkey.keyCode {
            if audioRecorder.isRecording {
                stopAndTranscribeRecording()
            }
            return true
        }
        return false
    }

    /// Минимальный интервал между переключениями по Fn — гасит дребезг клавиши
    /// (быстрая последовательность down→up→down от одного физического нажатия),
    /// который иначе мгновенно стартует и тут же останавливает запись (0 содержимого).
    private static let functionToggleDebounceInterval: TimeInterval = 0.35

    private func handleFunctionToggleHotkey(_ event: NSEvent) -> Bool {
        guard event.type == .flagsChanged else { return false }
        let isDown = event.modifierFlags.contains(.function)

        if isDown, !functionHotkeyIsDown {
            let now = Date()
            if let last = lastFunctionToggleDate, now.timeIntervalSince(last) < Self.functionToggleDebounceInterval {
                functionHotkeyIsDown = true
                DiagnosticsLog.write("toggle hotkey debounced interval=\(now.timeIntervalSince(last))")
                return true
            }
            functionHotkeyIsDown = true
            lastFunctionToggleDate = now
            if audioRecorder.isRecording {
                stopAndTranscribeRecording()
            } else if controlPanelState.canStartRecording {
                startRecordingWithOverlayMode(.toggle)
            }
            return true
        }
        if !isDown {
            functionHotkeyIsDown = false
        }
        return false
    }

    private func handleFunctionPushToTalkHotkey(_ event: NSEvent) -> Bool {
        guard event.type == .flagsChanged else { return false }
        let isDown = event.modifierFlags.contains(.function)

        if isDown, !functionHotkeyIsDown {
            functionHotkeyIsDown = true
            if !audioRecorder.isRecording, controlPanelState.canStartRecording {
                startRecordingWithOverlayMode(.pushToTalk)
            }
            return true
        }
        if !isDown, functionHotkeyIsDown {
            functionHotkeyIsDown = false
            if audioRecorder.isRecording {
                stopAndTranscribeRecording()
            }
            return true
        }
        return false
    }

    private func transcribe(audioURL: URL, durationSeconds: TimeInterval = 0) {
        Task.detached {
            do {
                let currentSettings = await MainActor.run { self.settings }
                let startedAt = Date()
                let modelURL = try currentSettings.modelURL()
                DiagnosticsLog.write("transcribe started binary=\(currentSettings.whisperBinaryPath) model=\(modelURL.path) audio=\(audioURL.path) bytes=\(DiagnosticsLog.byteCountDescription(for: audioURL)) language=\(currentSettings.effectiveTranscriptionLanguage)")

                // Бенчмарк на реальном корпусе (recordings/) показал: ffmpeg-препроцессинг
                // (trim+loudnorm) деградирует вывод whisper — теряется пунктуация/регистр,
                // изредка добавляются галлюцинации («Продолжение следует»). Whisper сам
                // нормализует громкость, а тишину лучше режет его VAD (silero). Поэтому
                // подаём сырое 16 кГц/моно аудио + VAD; ffmpeg в рантайме больше не нужен.
                let audioForTranscription = audioURL

                let command = WhisperCommand(
                    binaryURL: URL(fileURLWithPath: EngineLocator.path(for: "whisper-cli", fallback: currentSettings.whisperBinaryPath)),
                    modelURL: modelURL,
                    audioURL: audioForTranscription,
                    language: currentSettings.effectiveTranscriptionLanguage,
                    initialPrompt: currentSettings.initialPrompt,
                    vadEnabled: currentSettings.vadEnabled,
                    vadModelURL: currentSettings.vadModelURL()
                )

                var rawText: String
                if currentSettings.transcriptionProvider == .openAI {
                    DiagnosticsLog.write("transcribe via cloud model=\(currentSettings.openAITranscriptionModel.rawValue)")
                    rawText = try CloudTranscriptionService.transcribe(
                        audioURL: audioForTranscription,
                        apiKey: currentSettings.openAIAPIKey,
                        model: currentSettings.openAITranscriptionModel,
                        language: currentSettings.effectiveTranscriptionLanguage
                    )
                    DiagnosticsLog.write("transcribe cloud ok characters=\(rawText.count)")
                } else {
                    let server = WhisperServerService.shared
                    if server.isRunning {
                        do {
                            rawText = try server.transcribe(
                                audioURL: audioForTranscription,
                                language: currentSettings.effectiveTranscriptionLanguage,
                                prompt: currentSettings.initialPrompt
                            )
                            DiagnosticsLog.write("transcribe via warm-server ok characters=\(rawText.count)")
                        } catch {
                            DiagnosticsLog.write("warm-server failed, falling back to CLI: \(error.localizedDescription)")
                            rawText = try WhisperCLITranscriber().transcribe(command: command, timeoutSeconds: 120)
                        }
                    } else {
                        rawText = try WhisperCLITranscriber().transcribe(command: command, timeoutSeconds: 120)
                    }

                    // Safety-net: запись прошла silence-gate (там есть звук выше порога), но
                    // транскрипция вернула пустоту. Самая частая причина — VAD silero на
                    // CLI-пути (warm-server VAD не использует) счёл тихую/короткую речь
                    // «тишиной» и вырезал её целиком → диктовка терялась без следа.
                    // Повторяем БЕЗ VAD: лучше отдать сырой текст, чем потерять мысль.
                    if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       currentSettings.vadEnabled {
                        DiagnosticsLog.write("empty result with VAD → retry without VAD")
                        let noVADCommand = WhisperCommand(
                            binaryURL: URL(fileURLWithPath: EngineLocator.path(for: "whisper-cli", fallback: currentSettings.whisperBinaryPath)),
                            modelURL: modelURL,
                            audioURL: audioForTranscription,
                            language: currentSettings.effectiveTranscriptionLanguage,
                            initialPrompt: currentSettings.initialPrompt,
                            vadEnabled: false
                        )
                        rawText = try WhisperCLITranscriber().transcribe(command: noVADCommand, timeoutSeconds: 120)
                        DiagnosticsLog.write("retry without VAD characters=\(rawText.count)")
                    }
                }
                // Временный предобработанный файл больше не нужен — чистим, чтобы не копить мусор в /tmp.
                if audioForTranscription != audioURL {
                    try? FileManager.default.removeItem(at: audioForTranscription)
                }
                DiagnosticsLog.write("transcribe raw result characters=\(rawText.count)")
                let llmEndpoint: URL? = currentSettings.polishLevel == .localLLM
                    ? await MainActor.run { self.localLLMServer.chatEndpoint }
                    : nil
                let appContext = await MainActor.run {
                    let screenContext = self.screenContextReader.snapshot(
                        smartContextEnabled: currentSettings.smartContextEnabled
                    )
                    var profile = AppContextProfile.profile(
                        bundleIdentifier: self.dictationTargetApp?.bundleIdentifier,
                        localizedName: self.dictationTargetApp?.localizedName,
                        screenContext: screenContext
                    )
                    // Режим «Промпт для ИИ»: разовый хоткей (потребляется здесь) или
                    // постоянный тумбл. Никогда не переопределяем sensitive-поля (пароли).
                    let aiPromptActive = self.activeRecordingAIPromptOverride || currentSettings.aiPromptModeEnabled
                    self.activeRecordingAIPromptOverride = false
                    if aiPromptActive, !profile.isSensitive {
                        profile.format = .aiPrompt
                    }
                    DiagnosticsLog.write("context profile format=\(profile.format.rawValue) target=\(profile.displayName.isEmpty ? "unknown" : profile.displayName) screenContext=\(screenContext != nil) sensitive=\(profile.isSensitive)")
                    return profile
                }
                let polisher = TextPolisherFactory.make(
                    level: currentSettings.polishLevel,
                    dictionary: currentSettings.dictionaryReplacements,
                    removeFillers: currentSettings.removeFillerWords,
                    localLLMEndpoint: llmEndpoint,
                    context: appContext,
                    log: { DiagnosticsLog.write($0) }
                )
                // whisper рвёт текст переносами по сегментам (иногда посреди слова) —
                // склеиваем ДО полировки, иначе финал «нечёткий» и слова разорваны.
                let normalizedRaw = TextPostProcessor.normalizeTranscriptNewlines(rawText)
                let text = try await polisher.polish(normalizedRaw)
                let processingSeconds = Date().timeIntervalSince(startedAt)
                DiagnosticsLog.write("transcribe finished rawCharacters=\(rawText.count) polishedCharacters=\(text.count) processingSeconds=\(String(format: "%.2f", processingSeconds))")

                // Корпус для настройки распознавания — только если включено и есть звук/текст.
                // Sensitive contexts (password/secure fields) никогда не архивируем.
                // Делаем здесь (вне main), пока временный WAV ещё на диске.
                if currentSettings.saveRecordings,
                   !appContext.isSensitive,
                   !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    RecordingArchive.save(
                        audioURL: audioURL,
                        text: text,
                        rawText: rawText,
                        modelID: currentSettings.selectedModelID,
                        language: currentSettings.effectiveTranscriptionLanguage,
                        durationSeconds: durationSeconds,
                        processingSeconds: processingSeconds
                    )
                } else if appContext.isSensitive {
                    DiagnosticsLog.write("recording archive skipped reason=sensitiveContext")
                }
                // Временный WAV в /tmp/ всегда удаляем — RecordingArchive использует копию.
                try? FileManager.default.removeItem(at: audioURL)

                await MainActor.run {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        DiagnosticsLog.write("transcribe empty result")
                        self.setControlPanelState(.error(L.t("Распознанный текст пуст — попробуйте записать ещё раз.", "Transcription is empty — try recording again.")))
                        self.overlayController.show(state: .error(L.t("Пустой результат", "Empty result")))
                        self.scheduleOverlayDismiss(after: 2.5)
                        return
                    }

                    if appContext.isSensitive {
                        DiagnosticsLog.write("history append skipped reason=sensitiveContext")
                    } else if let historyStore = self.historyStore {
                        do {
                            try historyStore.append(DictationEntry(
                                modelID: currentSettings.selectedModelID,
                                durationSeconds: durationSeconds,
                                processingSeconds: processingSeconds,
                                text: text,
                                // Сырой текст храним только если полировка реально его изменила —
                                // тогда в истории доступен toggle «Undo AI Edit». Иначе отменять нечего.
                                rawText: normalizedRaw != text ? normalizedRaw : nil
                            ))
                            DiagnosticsLog.write("history append succeeded characters=\(text.count)")
                        } catch {
                            DiagnosticsLog.write("history append failed error=\(error.localizedDescription)")
                        }
                    }

                    // Накопительная статистика (не зависит от retention истории).
                    if appContext.isSensitive {
                        DiagnosticsLog.write("usage stats record skipped reason=sensitiveContext")
                    } else if let usageStatsStore = self.usageStatsStore {
                        do {
                            try usageStatsStore.recordDictation(
                                wordCount: UsageStatsStore.wordCount(of: text),
                                durationSeconds: durationSeconds,
                                modelID: currentSettings.selectedModelID
                            )
                        } catch {
                            DiagnosticsLog.write("usage stats record failed error=\(error.localizedDescription)")
                        }
                    } else {
                        DiagnosticsLog.write("history append skipped reason=noHistoryStore")
                    }

                    if currentSettings.autoPasteEnabled {
                        let target = self.dictationTargetApp
                        self.dictationTargetApp = nil
                        self.clipboardPasteService.copyAndPaste(text, into: target, autoEnter: currentSettings.autoEnterAfterPaste, pasteMode: currentSettings.pasteMode) { [weak self] outcome in
                            self?.handlePasteOutcome(outcome, text: text)
                        }
                    } else {
                        self.dictationTargetApp = nil
                        self.clipboardPasteService.copy(text)
                        DiagnosticsLog.write("paste skipped autoPaste=false copied characters=\(text.count)")
                        self.setControlPanelState(.copied)
                        self.overlayController.show(state: .copied)
                        self.scheduleOverlayDismiss(after: 1.6)
                    }
                }
            } catch {
                DiagnosticsLog.write("transcribe failed error=\(error.localizedDescription)")
                try? FileManager.default.removeItem(at: audioURL)
                await MainActor.run {
                    self.dictationTargetApp = nil
                    self.setControlPanelState(.error(error.localizedDescription))
                    self.overlayController.show(state: .error(error.localizedDescription))
                    self.scheduleOverlayDismiss(after: 3.0)
                }
            }
        }
    }

    /// Реакция на результат автовставки. Вставилось — просто прячем оверлей (текст уже
    /// на месте, лишнее подтверждение не нужно). Не вставилось (нет поля / нет доступа) —
    /// прячем оверлей и показываем карточку результата с текстом и кнопкой «Скопировать».
    private func handlePasteOutcome(_ outcome: PasteOutcome, text: String) {
        switch outcome {
        case .pasted:
            DiagnosticsLog.write("paste outcome=pasted characters=\(text.count)")
            setControlPanelState(.inserted)
            overlayController.hide()
        case .copiedNoTextField:
            DiagnosticsLog.write("paste outcome=copiedNoTextField characters=\(text.count)")
            setControlPanelState(.copied)
            overlayController.hide()
            resultCardController.show(text: text, hint: L.t("Поставьте курсор в поле и вставьте ⌘V", "Place the cursor in a field and paste with ⌘V"))
        case .copiedNeedsAccess:
            DiagnosticsLog.write("paste outcome=copiedNeedsAccess characters=\(text.count)")
            setControlPanelState(.copied)
            overlayController.hide()
            resultCardController.show(text: text, hint: L.t("Включите \(AppBrand.displayName) в «Универсальном доступе»", "Enable \(AppBrand.displayName) in Accessibility settings"))
        }
    }

    private func scheduleOverlayDismiss(after seconds: TimeInterval) {
        cancelOverlayDismiss()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.overlayController.hide()
            if !self.controlPanelState.canStopRecording {
                self.setControlPanelState(.idle)
            }
        }
        overlayDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func showTransientError(
        controlMessage: String,
        overlayMessage: String? = nil,
        dismissAfter seconds: TimeInterval = 3.0
    ) {
        DiagnosticsLog.write("transient error message=\(controlMessage)")
        functionHotkeyIsDown = false
        setControlPanelState(.error(controlMessage))
        overlayController.show(state: .error(overlayMessage ?? controlMessage))
        scheduleOverlayDismiss(after: seconds)
    }

    private func cancelOverlayDismiss() {
        overlayDismissWorkItem?.cancel()
        overlayDismissWorkItem = nil
    }

    @objc private func copyLastDictation() {
        do {
            guard let entry = try historyStore?.recent(limit: 1).first else {
                showTransientError(controlMessage: "History is empty.")
                return
            }

            clipboardPasteService.copy(entry.text)
            setControlPanelState(.copied)
            overlayController.show(state: .copied)
        } catch {
            showTransientError(controlMessage: error.localizedDescription)
        }
    }

    @objc private func openHistoryFile() {
        guard let historyStore else {
            showTransientError(controlMessage: L.t("История недоступна.", "History is unavailable."))
            return
        }

        if historyWindowController == nil {
            historyWindowController = HistoryWindowController(store: historyStore)
        }
        historyWindowController?.present()
    }

    @objc private func openMicrophoneSettings() {
        MicrophonePermission.openSystemSettings()
    }

    @objc private func openAccessibilitySettings() {
        // Нет доступа — показываем системный промпт (по явному клику пользователя),
        // иначе открываем панель настроек для ручного управления.
        if AccessibilityPermission.isTrusted {
            AccessibilityPermission.openSystemSettings()
        } else {
            _ = AccessibilityPermission.requestIfNeeded()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func showControlPanel() {
        if controlPanelWindowController == nil {
            controlPanelWindowController = ControlPanelWindowController(delegate: self)
        }

        applyActivationPolicy()
        updateControlPanel()
        controlPanelWindowController?.present()
    }

    @objc private func showOnboarding() {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController(
                hotkeyText: settings.toggleHotkey.displayText
            ) { [weak self] _ in
                guard let self else { return }
                self.settings.hasCompletedOnboarding = true
                self.saveSettings()
                self.onboardingWindowController = nil
                self.showControlPanel()
            }
        }
        applyActivationPolicy()
        onboardingWindowController?.present()
    }

    private func setControlPanelState(_ state: ControlPanelState) {
        controlPanelState = state
        updateControlPanel()
    }

    private func updateControlPanel() {
        controlPanelWindowController?.render(
            state: controlPanelState,
            recentEntry: recentHistoryEntry(),
            recentEntries: recentHistoryEntries(),
            usageDashboard: usageDashboard(),
            settings: settings,
            installedModelIDs: installedModelIDs(),
            isDownloadingModel: isDownloadingModel,
            downloadStatus: downloadStatus
        )
    }

    private func recentHistoryEntry() -> DictationEntry? {
        try? historyStore?.recent(limit: 1).first
    }

    private func recentHistoryEntries(searchQuery: String = "") -> [DictationEntry] {
        if searchQuery.isEmpty {
            return (try? historyStore?.recent(limit: 500)) ?? []
        }
        return (try? historyStore?.search(query: searchQuery, limit: 500)) ?? []
    }

    private func usageDashboard() -> UsageDashboardSnapshot {
        // Тоталы за всё время из накопительного стора (не урезается по retention).
        // Фоллбэк на историю, если стор недоступен.
        if let dashboard = try? usageStatsStore?.dashboardSnapshot() {
            return dashboard
        }
        let lifetime = DictationUsageSummary.make(from: (try? historyStore?.all()) ?? [])
        return UsageDashboardSnapshot(lifetime: lifetime, periods: UsagePeriod.allCases.map { .empty($0) }, currentStreak: 0)
    }

    private var selectedProfile: ModelProfile? {
        ModelProfile.profile(id: settings.selectedModelID)
    }

    private func installedModelIDs() -> Set<String> {
        Set(ModelProfile.builtInProfiles.compactMap { profile in
            let url = URL(fileURLWithPath: settings.modelDirectoryPath, isDirectory: true)
                .appendingPathComponent(profile.fileName)
            return FileManager.default.fileExists(atPath: url.path) ? profile.id : nil
        })
    }

    private func saveSettings() {
        do {
            try settingsStore?.save(settings)
            updateControlPanel()
        } catch {
            showTransientError(controlMessage: "Could not save settings: \(error.localizedDescription)")
        }
    }

    private func validateSelectedModelInstalled() -> Bool {
        guard let profile = selectedProfile else {
            DiagnosticsLog.write("model validation failed reason=unknownModel id=\(settings.selectedModelID)")
            showTransientError(controlMessage: "Unknown model: \(settings.selectedModelID)")
            return false
        }

        let modelURL = URL(fileURLWithPath: settings.modelDirectoryPath, isDirectory: true)
            .appendingPathComponent(profile.fileName)
        if FileManager.default.fileExists(atPath: modelURL.path) {
            DiagnosticsLog.write("model validation succeeded id=\(settings.selectedModelID) path=\(modelURL.path)")
            return true
        }

        // Выбранная модель не скачана. Не блокируем диктовку наглухо, если на диске
        // есть хотя бы одна другая установленная модель — переключаемся на неё
        // (предпочитая Turbo как лучший дефолт) и продолжаем с предупреждением.
        let installed = installedModelIDs()
        let fallbackID: String? = installed.contains("turbo")
            ? "turbo"
            : installed.sorted { lhs, rhs in
                (ModelProfile.profile(id: lhs)?.accuracyScore ?? 0) > (ModelProfile.profile(id: rhs)?.accuracyScore ?? 0)
            }.first
        if let fallbackID, let fallbackProfile = ModelProfile.profile(id: fallbackID) {
            DiagnosticsLog.write("model validation fallback reason=missingModel id=\(settings.selectedModelID) fallback=\(fallbackID)")
            settings.selectedModelID = fallbackID
            saveSettings()
            startWhisperServerIfPossible()
            showTransientError(controlMessage: L.t(
                "\(profile.displayName) ещё не скачана — временно использую \(fallbackProfile.displayName).",
                "\(profile.displayName) isn't downloaded yet — using \(fallbackProfile.displayName) for now."))
            return true
        }

        let message = profile.missingMessage
        DiagnosticsLog.write("model validation failed reason=missingModel id=\(settings.selectedModelID) path=\(modelURL.path)")
        showTransientError(controlMessage: message)
        return false
    }

    private func testAudioURL() throws -> URL {
        if let bundledURL = Bundle.main.url(forResource: "russian-test", withExtension: "wav") {
            return bundledURL
        }

        let workingDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            workingDirectoryURL.appendingPathComponent("tmp/russian-test.wav"),
            workingDirectoryURL.appendingPathComponent("wiki/personal/projects/personal-dictation-app/app/tmp/russian-test.wav")
        ]

        if let existingURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return existingURL
        }

        throw NSError(
            domain: AppBrand.executableName,
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Test audio file is missing from the app bundle."]
        )
    }

    private func downloadSelectedModel() {
        guard let profile = selectedProfile else { return }
        guard !isDownloadingModel else { return }

        isDownloadingModel = true
        lastReportedPercent = -1
        downloadStatus = L.t("Скачиваю \(profile.displayName) (\(profile.sizeLabel))...", "Downloading \(profile.displayName) (\(profile.sizeLabel))...")
        updateControlPanel()

        Task {
            do {
                let directory = URL(fileURLWithPath: settings.modelDirectoryPath, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(profile.fileName)
                let downloader = ModelDownloader()
                let temporaryURL = try await downloader.download(from: profile.downloadURL) { [weak self] progress in
                    Task { @MainActor in self?.reportDownloadProgress(progress, name: profile.displayName, kind: .whisper) }
                }
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                isDownloadingModel = false
                downloadStatus = L.t("\(profile.displayName) готова", "\(profile.displayName) ready")
                updateControlPanel()
            } catch {
                isDownloadingModel = false
                downloadStatus = L.t("Не удалось скачать: \(error.localizedDescription)", "Download failed: \(error.localizedDescription)")
                setControlPanelState(.error(downloadStatus))
            }
        }
    }

    /// Качает модель локальной полировки «Красиво» и после успеха прогревает сервер.
    private func downloadLocalLLMModel() {
        guard !isDownloadingModel else { return }
        let model = settings.selectedLLMModel

        isDownloadingModel = true
        lastReportedPercent = -1
        downloadStatus = L.t("Скачиваю модель «Красиво» \(model.displayName) (\(model.sizeLabel))...", "Downloading “Beautiful” model \(model.displayName) (\(model.sizeLabel))...")
        updateControlPanel()

        Task {
            do {
                let directory = URL(fileURLWithPath: settings.modelDirectoryPath, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = model.fileURL(inModelDirectory: settings.modelDirectoryPath)
                let downloader = ModelDownloader()
                let temporaryURL = try await downloader.download(from: model.downloadURL) { [weak self] progress in
                    Task { @MainActor in self?.reportDownloadProgress(progress, name: model.displayName, kind: .localLLM) }
                }
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                isDownloadingModel = false
                downloadStatus = L.t("Модель «Красиво» \(model.displayName) готова", "“Beautiful” model \(model.displayName) ready")
                updateControlPanel()
                // Если уровень уже «Красиво» — сразу поднимаем сервер.
                localLLMServer.ensureRunning(for: settings)
            } catch {
                isDownloadingModel = false
                downloadStatus = L.t("Не удалось скачать модель «Красиво»: \(error.localizedDescription)", "Failed to download “Beautiful” model: \(error.localizedDescription)")
                setControlPanelState(.error(downloadStatus))
            }
        }
    }

    private enum DownloadKind { case whisper, localLLM }

    /// Лёгкое обновление прогресса: НЕ дёргает полный `render` (тот читает всю
    /// историю с диска и сканирует ФС — на каждый чанк это вешало UI). Двигаем
    /// только нужный прогресс-бар и подпись, и только при смене целого процента.
    private func reportDownloadProgress(_ progress: ModelDownloadProgress, name: String, kind: DownloadKind) {
        let percent = Int(progress.fraction * 100)
        guard percent != lastReportedPercent else { return }
        lastReportedPercent = percent

        let sizeText = Self.byteProgressText(progress.bytesWritten, progress.bytesExpected)
        let label = L.t("\(name): \(percent)% · \(sizeText)", "\(name): \(percent)% · \(sizeText)")
        downloadStatus = label   // запомним для следующего полного render
        switch kind {
        case .whisper:
            controlPanelWindowController?.updateWhisperDownloadProgress(fraction: progress.fraction, label: label)
        case .localLLM:
            controlPanelWindowController?.updateLLMDownloadProgress(fraction: progress.fraction, label: label)
        }
    }

    /// «128 МБ из 1,93 ГБ» — человекочитаемый объём скачанного.
    private static func byteProgressText(_ written: Int64, _ total: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: written)) \(L.t("из", "of")) \(formatter.string(fromByteCount: total))"
    }
}

extension AppDelegate: ControlPanelWindowControllerDelegate {
    func controlPanelDidStartRecording() {
        startRecordingWithOverlayMode(.toggle)
    }

    func controlPanelDidStopAndTranscribe() {
        stopAndTranscribeRecording()
    }

    func controlPanelDidCancelRecording() {
        cancelRecording()
    }

    func controlPanelDidTranscribeTestAudio() {
        transcribeTestAudio()
    }

    func controlPanelDidSelectModel(id: String) {
        settings.selectedModelID = id
        downloadStatus = ""
        saveSettings()
        startWhisperServerIfPossible()
    }

    func controlPanelDidDownloadSelectedModel() {
        downloadSelectedModel()
    }

    func controlPanelDidDownloadLocalLLMModel() {
        downloadLocalLLMModel()
    }

    func controlPanelDidOpenModelDirectory() {
        let directory = URL(fileURLWithPath: settings.modelDirectoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func controlPanelDidApplySettings(
        language: String,
        initialPrompt: String,
        whisperBinaryPath: String,
        modelDirectoryPath: String
    ) {
        let defaults = AppSettings.defaultSettings()
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBinaryPath = whisperBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelDirectory = modelDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)

        settings.language = trimmedLanguage.isEmpty ? defaults.language : trimmedLanguage
        settings.initialPrompt = trimmedPrompt.isEmpty ? defaults.initialPrompt : trimmedPrompt
        settings.whisperBinaryPath = trimmedBinaryPath.isEmpty
            ? defaults.whisperBinaryPath
            : (trimmedBinaryPath as NSString).expandingTildeInPath
        settings.modelDirectoryPath = trimmedModelDirectory.isEmpty
            ? defaults.modelDirectoryPath
            : (trimmedModelDirectory as NSString).expandingTildeInPath
        downloadStatus = L.t("Настройки сохранены", "Settings saved")
        saveSettings()
    }

    func controlPanelDidSetPolishLevel(_ level: PolishLevel) {
        settings.polishLevel = level
        downloadStatus = L.t("Уровень полировки: \(level.displayTitle)", "Polish level: \(level.displayTitle)")
        saveSettings()
        // Поднимаем llama-server при выборе «Красиво», гасим при переключении прочь.
        if level == .localLLM {
            localLLMServer.ensureRunning(for: settings)
            let model = settings.selectedLLMModel
            if !model.isDownloaded(inModelDirectory: settings.modelDirectoryPath) {
                downloadStatus = L.t("Умная (ИИ): сначала скачайте модель \(model.displayName) (\(model.sizeLabel))", "Smart (AI): download the model first — \(model.displayName) (\(model.sizeLabel))")
            }
        } else {
            localLLMServer.stop()
        }
    }

    /// Пользователь выбрал другую модель полировки в каталоге. Сохраняем, и если активен
    /// уровень «Умная (ИИ)» — перезапускаем сервер с новой моделью (или подсказываем
    /// скачать, если её ещё нет на диске).
    func controlPanelDidSelectLLMModel(_ model: LocalLLMModel) {
        guard settings.selectedLLMModelID != model.id else { return }
        settings.selectedLLMModelID = model.id
        saveSettings()
        if settings.polishLevel == .localLLM {
            localLLMServer.stop()
            if model.isDownloaded(inModelDirectory: settings.modelDirectoryPath) {
                localLLMServer.ensureRunning(for: settings)
                downloadStatus = L.t("Модель полировки: \(model.displayName)", "Polish model: \(model.displayName)")
            } else {
                downloadStatus = L.t("Умная (ИИ): скачайте модель \(model.displayName) (\(model.sizeLabel))", "Smart (AI): download \(model.displayName) (\(model.sizeLabel))")
            }
        }
        updateControlPanel()
    }

    func controlPanelDidSetMediaInterruptionMode(_ mode: MediaInterruptionMode) {
        settings.mediaInterruptionMode = mode
        downloadStatus = L.t("Медиа во время записи: \(mode.displayTitle)", "Media while recording: \(mode.displayTitle)")
        saveSettings()
    }

    func controlPanelDidSetAutoPaste(_ enabled: Bool) {
        settings.autoPasteEnabled = enabled
        downloadStatus = enabled ? L.t("Автовставка включена", "Auto-paste enabled") : L.t("Автовставка выключена — только копирование", "Auto-paste off — copy only")
        saveSettings()
    }

    func controlPanelDidSetRemoveFillers(_ enabled: Bool) {
        settings.removeFillerWords = enabled
        downloadStatus = enabled ? L.t("Слова-паразиты будут убираться", "Filler words will be removed") : L.t("Слова-паразиты сохраняются", "Filler words are kept")
        saveSettings()
    }

    func controlPanelDidSetAIPromptModeEnabled(_ enabled: Bool) {
        settings.aiPromptModeEnabled = enabled
        downloadStatus = enabled
            ? L.t("Каждая диктовка станет промптом для ИИ", "Every dictation becomes an AI prompt")
            : L.t("Режим «Промпт для ИИ» выключен", "“AI Prompt” mode disabled")
        saveSettings()
    }

    func controlPanelDidSetSmartContext(_ enabled: Bool) {
        settings.smartContextEnabled = enabled
        if enabled, !AccessibilityPermission.isTrusted {
            downloadStatus = L.t(
                "Умный контекст включён, но для активного поля нужен доступ Accessibility",
                "Smart context enabled, but active-field reading needs Accessibility access"
            )
        } else {
            downloadStatus = enabled
                ? L.t("Умный контекст включён", "Smart context enabled")
                : L.t("Умный контекст выключен", "Smart context disabled")
        }
        saveSettings()
    }

    func controlPanelDidSetLaunchAtLogin(_ enabled: Bool) {
        let actual = LoginItemService.setEnabled(enabled)
        settings.launchAtLogin = actual
        downloadStatus = actual
            ? L.t("Запуск при входе в систему включён", "Launch at login enabled")
            : (enabled
                ? L.t("Не удалось включить автозапуск — проверьте «Системные настройки → Элементы входа»",
                      "Couldn't enable launch at login — check System Settings → Login Items")
                : L.t("Запуск при входе в систему выключен", "Launch at login disabled"))
        saveSettings()
    }

    func controlPanelDidSetShowInDock(_ enabled: Bool) {
        settings.showInDock = enabled
        applyActivationPolicy()
        downloadStatus = enabled
            ? L.t("Иконка показывается в Dock", "Icon shown in the Dock")
            : L.t("Только в строке меню (без Dock)", "Menu bar only (no Dock)")
        saveSettings()
    }

    func controlPanelDidSetPlaySounds(_ enabled: Bool) {
        settings.playFeedbackSounds = enabled
        feedbackSoundPlayer.isEnabled = enabled
        downloadStatus = enabled
            ? L.t("Звук уведомления включён", "Notification sound enabled")
            : L.t("Звук уведомления выключен", "Notification sound disabled")
        saveSettings()
    }

    func controlPanelDidSetSaveRecordings(_ enabled: Bool) {
        settings.saveRecordings = enabled
        downloadStatus = enabled
            ? L.t("Записи сохраняются в папку Recordings (локально)", "Recordings saved to the Recordings folder (local)")
            : L.t("Сохранение записей выключено", "Saving recordings disabled")
        saveSettings()
    }

    func controlPanelDidSetVADEnabled(_ enabled: Bool) {
        settings.vadEnabled = enabled
        downloadStatus = enabled
            ? L.t("VAD включён — паузы будут обрезаться", "VAD enabled — silence will be trimmed")
            : L.t("VAD выключен", "VAD disabled")
        saveSettings()
    }

    func controlPanelDidSetAudioNormalization(_ enabled: Bool) {
        settings.audioNormalizationEnabled = enabled
        downloadStatus = enabled
            ? L.t("Нормализация аудио включена", "Audio normalization enabled")
            : L.t("Нормализация аудио выключена", "Audio normalization disabled")
        saveSettings()
    }

    func controlPanelDidSetAutoEnterAfterPaste(_ enabled: Bool) {
        settings.autoEnterAfterPaste = enabled
        downloadStatus = enabled
            ? L.t("Enter после вставки включён", "Auto-Enter after paste enabled")
            : L.t("Enter после вставки выключен", "Auto-Enter after paste disabled")
        saveSettings()
    }

    func controlPanelDidSetInputDevice(uid: String) {
        settings.inputDeviceUID = uid
        saveSettings()
    }

    func controlPanelDidSetSpokenLanguages(_ codes: [String], autoDetect: Bool) {
        settings.spokenLanguages = codes
        settings.autoDetectLanguage = autoDetect
        // Держим legacy-поле `language` синхронным с эффективным значением (для совместимости
        // и бандла applySettings). Сервер берёт язык на каждый запрос — рестарт не нужен.
        settings.language = autoDetect ? "auto" : (codes.first ?? "auto")
        saveSettings()
        DiagnosticsLog.write("spoken languages set codes=\(codes) autoDetect=\(autoDetect) effective=\(settings.effectiveTranscriptionLanguage)")
    }

    func controlPanelDidSetPasteMode(_ mode: PasteMode) {
        settings.pasteMode = mode
        saveSettings()
    }

    func controlPanelDidSetTranscriptionProvider(_ provider: TranscriptionProvider) {
        settings.transcriptionProvider = provider
        saveSettings()
        startWhisperServerIfPossible()
    }

    func controlPanelDidSetOpenAIAPIKey(_ key: String) {
        settings.openAIAPIKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        saveSettings()
    }

    func controlPanelDidSetOpenAIModel(_ model: OpenAITranscriptionModel) {
        settings.openAITranscriptionModel = model
        saveSettings()
    }

    func controlPanelDidSearchHistory(query: String) {
        let results = recentHistoryEntries(searchQuery: query)
        controlPanelWindowController?.render(
            state: controlPanelState,
            recentEntry: recentHistoryEntry(),
            recentEntries: results,
            usageDashboard: usageDashboard(),
            settings: settings,
            installedModelIDs: installedModelIDs(),
            isDownloadingModel: isDownloadingModel,
            downloadStatus: downloadStatus
        )
    }

    func controlPanelDidSetOverlayDisplayMode(_ mode: OverlayDisplayMode) {
        settings.overlayDisplayMode = mode
        try? settingsStore?.save(settings)
        overlayController.displayMode = mode
        // Если переключились в режим без оверлея — скрыть если показан.
        if mode == .none { overlayController.hide() }
    }

    func controlPanelDidSetAutomaticallyCheckForUpdates(_ enabled: Bool) {
        settings.automaticallyCheckForUpdates = enabled
        saveSettings()
    }

    func controlPanelDidRequestCheckForUpdates() {
        downloadStatus = L.t("Проверяю обновления…", "Checking for updates…")
        updateControlPanel()
        Task { @MainActor in
            let result = await UpdateChecker.checkLatestRelease(currentVersion: AppBrand.versionString)
            switch result {
            case .upToDate:
                downloadStatus = L.t(
                    "У вас последняя версия (\(AppBrand.versionString))",
                    "You're up to date (\(AppBrand.versionString))")
            case .updateAvailable(let version, let url):
                downloadStatus = L.t(
                    "Доступна версия \(version) — открываю страницу релиза",
                    "Version \(version) available — opening release page")
                NSWorkspace.shared.open(url)
            case .failed:
                downloadStatus = L.t("Не удалось проверить обновления", "Couldn't check for updates")
            }
            DiagnosticsLog.write("check for updates result=\(result) version=\(AppBrand.versionString)")
            updateControlPanel()
        }
    }

    func controlPanelDidSetDiagnosticsLogging(_ enabled: Bool) {
        settings.diagnosticsLoggingEnabled = enabled
        DiagnosticsLog.isEnabled = enabled
        saveSettings()
    }

    func controlPanelDidRequestShowDiagnosticsLog() {
        DiagnosticsLog.revealInFinder()
    }

    func controlPanelDidSetRecordingsRetention(_ retention: RecordingsRetentionPeriod) {
        settings.recordingsRetention = retention
        saveSettings()
        RecordingArchive.pruneOldRecordings(retention: retention)
    }

    func controlPanelDidSetInterfaceLanguage(_ code: String) {
        guard settings.interfaceLanguage != code else { return }
        settings.interfaceLanguage = code
        try? settingsStore?.save(settings)
        applyInterfaceLanguageFromSettings()
        // Отложенно (после закрытия модалки-пикера) пересобираем панель целиком,
        // чтобы все строки перестроились на новом языке без конфликта со sheet.
        DispatchQueue.main.async { [weak self] in
            self?.rebuildLocalizedInterface()
        }
    }

    func controlPanelDidSetDictionary(_ entries: [DictionaryEntry]) {
        settings.dictionaryReplacements = entries
        downloadStatus = L.t("Словарь сохранён: \(entries.count) замен", "Dictionary saved: \(entries.count) replacements")
        saveSettings()
    }

    func controlPanelDidSetHotkey(_ hotkey: Hotkey, for action: DictationHotkeyAction) {
        guard hotkey.isAssignable else {
            downloadStatus = L.t("Нажмите сочетание с обычной клавишей или Fn отдельно", "Press a shortcut with a regular key, or Fn on its own")
            saveSettings()
            return
        }

        switch action {
        case .toggleRecording:
            guard hotkey != settings.pushToTalkHotkey else {
                downloadStatus = L.t("Эта клавиша уже назначена для режима «Зажать»", "This key is already assigned to Hold")
                saveSettings()
                return
            }
            settings.toggleHotkey = hotkey
            downloadStatus = L.t("Старт/Стоп сохранён: \(hotkey.displayText)", "Start/Stop saved: \(hotkey.displayText)")
        case .pushToTalk:
            guard hotkey != settings.toggleHotkey else {
                downloadStatus = L.t("Эта клавиша уже назначена для «Старт/Стоп»", "This key is already assigned to Start/Stop")
                saveSettings()
                return
            }
            settings.pushToTalkHotkey = hotkey
            downloadStatus = L.t("Зажать для диктовки сохранено: \(hotkey.displayText)", "Hold-to-dictate saved: \(hotkey.displayText)")
        case .aiPrompt:
            guard hotkey != settings.toggleHotkey, hotkey != settings.pushToTalkHotkey else {
                downloadStatus = L.t("Эта клавиша уже занята другим действием", "This key is already used by another action")
                saveSettings()
                return
            }
            settings.aiPromptHotkey = hotkey
            downloadStatus = L.t("«Промпт для ИИ» сохранён: \(hotkey.displayText)", "“AI Prompt” saved: \(hotkey.displayText)")
        }

        saveSettings()
        functionHotkeyIsDown = false
        startAppShortcutMonitors()
    }

    func controlPanelDidClearAIPromptHotkey() {
        settings.aiPromptHotkey = AppSettings.unassignedHotkey
        downloadStatus = L.t("«Промпт для ИИ» сброшен", "“AI Prompt” shortcut cleared")
        saveSettings()
        functionHotkeyIsDown = false
        startAppShortcutMonitors()
    }

    func controlPanelDidCopyLastDictation() {
        copyLastDictation()
    }

    func controlPanelDidOpenHistory() {
        openHistoryFile()
    }

    func controlPanelDidCopyText(_ text: String) {
        // Тихое копирование того, что сейчас видно в строке (сырой или финальный текст):
        // подтверждение — анимация-галочка на самой иконке (HistoryIconButton.flashOnSuccess).
        // Без оверлея внизу и без setControlPanelState (он бы пересобрал строки и оборвал анимацию).
        clipboardPasteService.copy(text)
    }

    func controlPanelDidDeleteEntry(id: UUID) {
        try? historyStore?.delete(id: id)
        updateControlPanel()
    }

    func controlPanelDidClearHistory() {
        try? historyStore?.clear()
        updateControlPanel()
    }

    func controlPanelDidOpenMicrophoneSettings() {
        openMicrophoneSettings()
    }

    func controlPanelDidOpenAccessibilitySettings() {
        openAccessibilitySettings()
    }
}

extension AppDelegate: OverlayControllerDelegate {
    func overlayDidAccept() {
        guard audioRecorder.isRecording else {
            overlayController.hide()
            return
        }

        stopAndTranscribeRecording()
    }

    func overlayDidCancel() {
        cancelRecording()
    }
}

private extension HotkeyMode {
    var displayTitle: String {
        switch self {
        case .toggle:
            return L.t("Переключение", "Toggle")
        case .pushToTalk:
            return L.t("Зажать", "Hold")
        }
    }
}

private extension PolishLevel {
    var displayTitle: String {
        switch self {
        case .rules:
            return L.t("Правила", "Rules")
        case .localLLM:
            return L.t("Красиво (локальная LLM)", "Beautiful (local LLM)")
        case .cloud:
            return L.t("Облако", "Cloud")
        }
    }
}

private extension MediaInterruptionMode {
    var displayTitle: String {
        switch self {
        case .none:
            return L.t("Не трогать", "Leave alone")
        case .pause:
            return L.t("Пауза", "Pause")
        case .duck:
            return L.t("Приглушить", "Duck")
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshBehaviorMenuState()
    }
}

private extension NSEvent {
    func matches(_ hotkey: Hotkey) -> Bool {
        if hotkey == .fn {
            return type == .flagsChanged && modifierFlags.contains(.function)
        }
        guard UInt16(keyCode) == hotkey.keyCode else { return false }
        return Set(hotkey.modifierFlags) == Set(modifierNames)
    }

    var modifierNames: [String] {
        var names: [String] = []
        if modifierFlags.contains(.control) { names.append("control") }
        if modifierFlags.contains(.option) { names.append("option") }
        if modifierFlags.contains(.shift) { names.append("shift") }
        if modifierFlags.contains(.command) { names.append("command") }
        if modifierFlags.contains(.function) { names.append("function") }
        return names
    }
}
