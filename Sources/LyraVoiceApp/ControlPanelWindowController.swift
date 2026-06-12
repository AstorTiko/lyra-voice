import AppKit
import LyraVoiceCore

@MainActor
protocol ControlPanelWindowControllerDelegate: AnyObject {
    func controlPanelDidStartRecording()
    func controlPanelDidStopAndTranscribe()
    func controlPanelDidCancelRecording()
    func controlPanelDidTranscribeTestAudio()
    func controlPanelDidSelectModel(id: String)
    func controlPanelDidDownloadSelectedModel()
    func controlPanelDidDownloadLocalLLMModel()
    func controlPanelDidOpenModelDirectory()
    func controlPanelDidSetHotkey(_ hotkey: Hotkey, for action: DictationHotkeyAction)
    func controlPanelDidApplySettings(
        language: String,
        initialPrompt: String,
        whisperBinaryPath: String,
        modelDirectoryPath: String
    )
    func controlPanelDidSetPolishLevel(_ level: PolishLevel)
    func controlPanelDidSetMediaInterruptionMode(_ mode: MediaInterruptionMode)
    func controlPanelDidSetAutoPaste(_ enabled: Bool)
    func controlPanelDidSetRemoveFillers(_ enabled: Bool)
    func controlPanelDidSetSmartContext(_ enabled: Bool)
    func controlPanelDidSetLaunchAtLogin(_ enabled: Bool)
    func controlPanelDidSetShowInDock(_ enabled: Bool)
    func controlPanelDidSetPlaySounds(_ enabled: Bool)
    func controlPanelDidSetSaveRecordings(_ enabled: Bool)
    func controlPanelDidSetVADEnabled(_ enabled: Bool)
    func controlPanelDidSetAudioNormalization(_ enabled: Bool)
    func controlPanelDidSetAutoEnterAfterPaste(_ enabled: Bool)
    func controlPanelDidSetDictionary(_ entries: [DictionaryEntry])
    func controlPanelDidCopyLastDictation()
    func controlPanelDidOpenHistory()
    func controlPanelDidCopyText(_ text: String)
    func controlPanelDidDeleteEntry(id: UUID)
    func controlPanelDidClearHistory()
    func controlPanelDidOpenMicrophoneSettings()
    func controlPanelDidOpenAccessibilitySettings()
    func controlPanelDidSetInputDevice(uid: String)
    func controlPanelDidSetSpokenLanguages(_ codes: [String], autoDetect: Bool)
    func controlPanelDidSetInterfaceLanguage(_ code: String)
    func controlPanelDidSetPasteMode(_ mode: PasteMode)
    func controlPanelDidSetTranscriptionProvider(_ provider: TranscriptionProvider)
    func controlPanelDidSetOpenAIAPIKey(_ key: String)
    func controlPanelDidSetOpenAIModel(_ model: OpenAITranscriptionModel)
    func controlPanelDidSearchHistory(query: String)
    func controlPanelDidSetOverlayDisplayMode(_ mode: OverlayDisplayMode)
    func controlPanelDidSetAutomaticallyCheckForUpdates(_ enabled: Bool)
    func controlPanelDidRequestCheckForUpdates()
    func controlPanelDidSetDiagnosticsLogging(_ enabled: Bool)
    func controlPanelDidRequestShowDiagnosticsLog()
    func controlPanelDidSetRecordingsRetention(_ retention: RecordingsRetentionPeriod)
}

@MainActor
final class ControlPanelWindowController: NSWindowController {
    private let controlView = ControlPanelView(frame: NSRect(x: 0, y: 0, width: 920, height: 680))

    init(delegate: ControlPanelWindowControllerDelegate) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.isReleasedWhenClosed = false
        window.center()
        window.contentMinSize = NSSize(width: 860, height: 600)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        // isOpaque = false нужен чтобы NSVisualEffectView в сайдбаре мог показывать
        // behindWindow-blur (Liquid Glass). Контентная часть остаётся непрозрачной
        // через layer.backgroundColor в ControlPanelView.
        window.isOpaque = false
        window.backgroundColor = DS.Color.base
        window.isMovableByWindowBackground = true
        super.init(window: window)

        controlView.delegate = delegate
        window.contentView = controlView
        // Не фокусировать автоматически ни одно поле при открытии окна.
        window.initialFirstResponder = nil
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        // Политику активации (Dock vs только меню) задаёт AppDelegate по настройке.
        NSApp.unhide(nil)
        placeInsideVisibleScreen(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        // Снимаем фокус с любого поля ввода — пользователь выбирает сам куда кликнуть.
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(nil)
        }
    }

    private func placeInsideVisibleScreen(_ window: NSWindow) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 56
        let width = min(window.frame.width, max(visibleFrame.width - margin * 2, 820))
        let height = min(window.frame.height, max(visibleFrame.height - margin * 2, 560))
        let x = visibleFrame.minX + max(margin, (visibleFrame.width - width) / 2)
        let y = visibleFrame.maxY - height - margin
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    func render(
        state: ControlPanelState,
        recentEntry: DictationEntry?,
        recentEntries: [DictationEntry],
        usageDashboard: UsageDashboardSnapshot,
        settings: AppSettings,
        installedModelIDs: Set<String>,
        isDownloadingModel: Bool,
        downloadStatus: String
    ) {
        controlView.render(
            state: state,
            recentEntry: recentEntry,
            historyEntries: recentEntries,
            usageDashboard: usageDashboard,
            settings: settings,
            installedModelIDs: installedModelIDs,
            isDownloadingModel: isDownloadingModel,
            downloadStatus: downloadStatus
        )
    }

    /// Лёгкое обновление прогресса Whisper-модели — без полного `render`.
    func updateWhisperDownloadProgress(fraction: Double, label: String) {
        controlView.updateWhisperDownloadProgress(fraction: fraction, label: label)
    }

    /// Лёгкое обновление прогресса модели «Красиво» (Qwen) — без полного `render`.
    func updateLLMDownloadProgress(fraction: Double, label: String) {
        controlView.updateLLMDownloadProgress(fraction: fraction, label: label)
    }
}

// MARK: - Разделы навигации

private typealias PanelSection = ControlPanelSection

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Heatmap-календарь активности (B8, как «N day streak» у Wispr Flow): сетка дней
/// 7 в ширину (Пн-Вс), цвет ячейки — интенсивность по числу диктовок за день.
/// День/неделя — одна строка без выравнивания по дню недели; месяц (30 дней) —
/// несколько строк с отступом по дню недели первого дня, как в GitHub-календаре.
private final class UsageActivityChartView: NSView {
    private static let columns = 7
    private static let cellSize: CGFloat = 13
    private static let gap: CGFloat = 4

    var dailyUsage: [DailyUsage] = [] {
        didSet { needsDisplay = true }
    }

    /// Высота, нужная сетке для текущего `dailyUsage` (включая внутренние отступы 10pt).
    var preferredHeight: CGFloat {
        let rows = max(1, rowCount)
        return CGFloat(rows) * Self.cellSize + CGFloat(rows - 1) * Self.gap + 20
    }

    private var rowCount: Int {
        guard dailyUsage.count > Self.columns else { return 1 }
        let leadingPad = dailyUsage.first.map { Self.weekdayIndex(of: $0.day) } ?? 0
        return Int(ceil(Double(leadingPad + dailyUsage.count) / Double(Self.columns)))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = DS.Radius.control
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = DS.Color.surfaceSunken.withAlphaComponent(0.42).cgColor
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !dailyUsage.isEmpty else {
            drawEmptyLine()
            return
        }

        let rect = bounds.insetBy(dx: 12, dy: 10)
        let columns = Self.columns
        let leadingPad = dailyUsage.count > columns ? Self.weekdayIndex(of: dailyUsage[0].day) : 0
        let rows = rowCount
        let gap = Self.gap
        let cellSize = Self.cellSize
        let gridWidth = cellSize * CGFloat(columns) + gap * CGFloat(columns - 1)
        let gridHeight = cellSize * CGFloat(rows) + gap * CGFloat(rows - 1)
        let originX = rect.minX + max(0, (rect.width - gridWidth) / 2)
        let originY = rect.minY + max(0, (rect.height - gridHeight) / 2)

        let maxValue = max(1, dailyUsage.map(\.dictationCount).max() ?? 0)

        for (index, day) in dailyUsage.enumerated() {
            let cellIndex = leadingPad + index
            let col = cellIndex % columns
            let row = cellIndex / columns
            let x = originX + CGFloat(col) * (cellSize + gap)
            let y = originY + CGFloat(row) * (cellSize + gap)
            let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: cellSize, height: cellSize), xRadius: 3, yRadius: 3)
            color(for: day.dictationCount, max: maxValue).setFill()
            path.fill()
        }
    }

    private func color(for count: Int, max maxValue: Int) -> NSColor {
        guard count > 0 else { return DS.Color.surfaceBorder.withAlphaComponent(0.35) }
        let fraction = Double(count) / Double(maxValue)
        let alpha: CGFloat
        switch fraction {
        case ..<0.25: alpha = 0.35
        case ..<0.5: alpha = 0.55
        case ..<0.75: alpha = 0.78
        default: alpha = 1.0
        }
        return DS.Color.accent.withAlphaComponent(alpha)
    }

    /// Индекс дня недели для календарной сетки: Пн=0 … Вс=6 (независимо от локали).
    private static func weekdayIndex(of date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date) // Вс=1 … Сб=7
        return (weekday + 5) % 7
    }

    private func drawEmptyLine() {
        let rect = bounds.insetBy(dx: 14, dy: 28)
        let path = NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: 2), xRadius: 1, yRadius: 1)
        DS.Color.surfaceBorder.withAlphaComponent(0.7).setFill()
        path.fill()
    }
}

@MainActor
private final class ControlPanelView: NSView {
    private let showsSidebarFutureSlots = false

    weak var delegate: ControlPanelWindowControllerDelegate?

    // Контролы
    private let statusTitleLabel = NSTextField(labelWithString: "")
    private let statusDetailLabel = NSTextField(labelWithString: "")
    private let greetingTitleLabel = NSTextField(labelWithString: "")
    private let greetingDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let dictationCountLabel = NSTextField(labelWithString: "0")
    private let wordCountLabel = NSTextField(labelWithString: "0")
    private let durationLabel = NSTextField(labelWithString: "0")
    private let usageActivityChart = UsageActivityChartView()
    private let usageActiveDaysLabel = NSTextField(labelWithString: "0")
    private let usageSessionsLabel = NSTextField(labelWithString: "0")
    private let usageStreakLabel = NSTextField(labelWithString: "0")
    private let usageLongestStreakLabel = NSTextField(labelWithString: "0")
    private var usageActivityChartHeight: NSLayoutConstraint!
    private var currentUsageDashboard: UsageDashboardSnapshot = .empty
    // Левая колонка Home — прокручиваемая история по датам.
    // Кастомный стек ведёт hover централизованно (ровно одна строка под курсором).
    private let homeHistoryStack = HistoryListStackView()
    private let historySearchField = NSSearchField()
    private var allHistoryEntries: [DictationEntry] = []
    private let homeHistoryScroll = NSScrollView()
    // Ленивый + порционный рендер истории: список строится только когда раздел
    // истории виден, и вставляется порциями — чтобы открытие было мгновенным,
    // а не упиралось в синхронную раскладку сотен многострочных строк.
    private var pendingHistoryEntries: [DictationEntry] = []
    private var pendingHistorySearching = false
    private var historyNeedsRender = false
    private var historyRenderToken = 0
    private static let historyChunkSize = 25
    private static let historyFirstChunkSize = 8   // синхронная первая порция (под вьюпорт)
    private enum HistoryListItem { case dayHeader(String); case entry(DictationEntry) }
    private var startButton: StyledButton!
    private var stopButton: StyledButton!
    private var cancelButton: StyledButton!
    private var testAudioButton: StyledButton!
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var modelOptionViews: [String: ModelOptionView] = [:]
    private let modelStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let modelComparisonLabel = NSTextField(wrappingLabelWithString: "")
    private let downloadProgressIndicator = NSProgressIndicator()
    private var downloadModelButton: StyledButton!
    private var openModelsFolderButton: StyledButton!
    private let toggleHotkeyLabel = NSTextField(labelWithString: "")
    private let pushToTalkHotkeyLabel = NSTextField(labelWithString: "")
    private var setToggleHotkeyButton: StyledButton!
    private var setPushToTalkHotkeyButton: StyledButton!
    private let languageField = InsetTextField(string: "")
    private var languageRow: SettingsDisclosureRow!
    private let promptField = InsetTextField(string: "")
    private let whisperBinaryPathField = InsetTextField(string: "")
    private let modelDirectoryPathField = InsetTextField(string: "")
    private var applySettingsButton: StyledButton!
    private let polishLevelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let polishLevelSelector = OptionSelectorView()
    private let cloudPolishHint = NSTextField(wrappingLabelWithString: "")
    private var cloudPolishPanel: NSView?
    private let llmModelHint = NSTextField(wrappingLabelWithString: "")
    private let llmModelNameLabel = NSTextField(labelWithString: "")
    private let llmSizeBadge = NSTextField(labelWithString: "")
    private let llmDownloadProgress = NSProgressIndicator()
    private let llmReadyBadge = NSTextField(labelWithString: "")
    private var downloadLLMModelButton: StyledButton!
    private let mediaInterruptionSelector = OptionSelectorView()
    private var autoPasteToggle: SettingsToggleRow!
    private var removeFillersToggle: SettingsToggleRow!
    private var smartContextToggle: SettingsToggleRow!
    private var launchAtLoginToggle: SettingsToggleRow!
    private var showInDockToggle: SettingsToggleRow!
    private var playSoundsToggle: SettingsToggleRow!
    private var saveRecordingsToggle: SettingsToggleRow!
    private var recordingsRetentionRow: SettingsDisclosureRow!
    private var recordingsRetentionPickerSheet: OptionPickerSheet?
    private var currentRecordingsRetention = RecordingsRetentionPeriod.forever.rawValue
    private var automaticUpdatesToggle: SettingsToggleRow!
    private var checkForUpdatesButton: StyledButton!
    private var diagnosticsLoggingToggle: SettingsToggleRow!
    private var showDiagnosticsLogButton: StyledButton!
    private var autoEnterToggle: SettingsToggleRow!
    private var simulateTypingToggle: SettingsToggleRow!
    private var overlayModeRow: SettingsDisclosureRow!
    private var overlayModePickerSheet: OptionPickerSheet?
    private var transcriptionProviderSelector = OptionSelectorView()
    private let openAIKeyField = NSSecureTextField()
    private var openAIModelRow: SettingsDisclosureRow!
    private var openAIModelPickerSheet: OptionPickerSheet?
    private var currentOpenAIModel: OpenAITranscriptionModel = .gpt4oTranscribe
    private var openAIFieldsContainer: NSView?
    /// Карточка выбора локальной whisper-модели. Скрывается, когда выбран облачный
    /// провайдер (OpenAI) — локальные модели для него не нужны.
    private var localModelCard: NSView?
    private var languagesPickerSheet: LanguagesPickerSheet?
    private var currentSpokenLanguages: [String] = []
    private var currentAutoDetectLanguage = true
    private var microphoneRow: SettingsDisclosureRow!
    private var interfaceLanguageRow: SettingsDisclosureRow!
    private var microphonePickerSheet: OptionPickerSheet?
    private var interfaceLanguagePickerSheet: OptionPickerSheet?
    private var currentInputDeviceUID = ""
    private var currentInterfaceLanguage = AppSettings.automaticInterfaceLanguage
    private var currentOverlayDisplayMode = OverlayDisplayMode.streaming.rawValue
    private let dictionaryEditor = DictionaryEditorView()
    private var copyLastButton: StyledButton!
    private var openHistoryButton: StyledButton!
    private var microphoneButton: StyledButton!
    private var accessibilityButton: StyledButton!
    // Индикаторы статуса разрешений: «● Разрешено» (зелёный) / «● Нужен доступ» (янтарный).
    private let microphoneStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private static let permissionAmber = NSColor(red: 0.98, green: 0.75, blue: 0.36, alpha: 1)
    // Чуть ярче, чем DS.Color.success — статус «выдано» должен читаться сразу.
    private static let permissionGreen = NSColor(red: 0.22, green: 0.92, blue: 0.50, alpha: 1)
    private var hotkeyCaptureMonitor: Any?

    // Навигация
    private let contentScroll = NSScrollView()
    private var pages: [PanelSection: NSView] = [:]
    private var sidebarItems: [PanelSection: SidebarItem] = [:]
    private var currentSection: PanelSection = .home
    private var contentWidthConstraint: NSLayoutConstraint?
    private var contentHeightConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Сплошная тёмная подложка под всем окном — рабочий стол не просвечивает.
        layer?.backgroundColor = DS.Color.base.cgColor
        buildControls()
        buildLayout()
        select(.home)
        // Возврат из «Системных настроек» делает приложение активным — обновляем
        // индикаторы разрешений, чтобы зелёный/янтарный статус был актуальным.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appDidBecomeActive() {
        renderPermissions()
    }

    // MARK: - Render

    func render(
        state: ControlPanelState,
        recentEntry: DictationEntry?,
        historyEntries: [DictationEntry],
        usageDashboard: UsageDashboardSnapshot,
        settings: AppSettings,
        installedModelIDs: Set<String>,
        isDownloadingModel: Bool,
        downloadStatus: String
    ) {
        statusTitleLabel.stringValue = state.statusTitle
        statusDetailLabel.stringValue = state.statusDetail
        renderHome(historyEntries: historyEntries, usageDashboard: usageDashboard)
        startButton.isEnabled = state.canStartRecording
        stopButton.isEnabled = state.canStopRecording
        cancelButton.isEnabled = state.canCancelRecording
        testAudioButton.isEnabled = state.canRunTestAudio

        renderModelSettings(
            settings: settings,
            installedModelIDs: installedModelIDs,
            isDownloadingModel: isDownloadingModel,
            downloadStatus: downloadStatus
        )
        renderSettings(settings)
        renderLocalLLMControls(settings: settings, isDownloadingModel: isDownloadingModel, downloadStatus: downloadStatus)
        renderPermissions()
    }

    /// Статус, прогресс и кнопка модели локальной полировки «Красиво».
    private func renderLocalLLMControls(settings: AppSettings, isDownloadingModel: Bool, downloadStatus: String) {
        let model = LocalLLMModel.default
        let downloaded = model.isDownloaded(inModelDirectory: settings.modelDirectoryPath)
        let isLLMSelected = settings.polishLevel == .localLLM

        llmModelNameLabel.stringValue = model.displayName
        llmSizeBadge.stringValue = model.sizeLabel
        llmSizeBadge.isHidden = downloaded
        llmReadyBadge.isHidden = !downloaded

        if isDownloadingModel {
            // Текст/прогресс во время загрузки ведёт лёгкий путь updateLLMDownloadProgress.
        } else if downloaded {
            llmModelHint.stringValue = isLLMSelected
                ? L.t("Модель готова. Полировка идёт локально и офлайн.",
                      "Model is ready. Polishing runs locally and offline.")
                : L.t("Модель скачана. Выберите «Умная (ИИ)» выше, чтобы включить.",
                      "Model downloaded. Pick “Smart (AI)” above to enable it.")
            llmDownloadProgress.isHidden = true
            llmDownloadProgress.doubleValue = 1
        } else {
            llmModelHint.stringValue = L.t(
                "Локальная модель для режима «Умная (ИИ)» — чистит грамматику и абзацы офлайн. Скачивается один раз.",
                "Local model for “Smart (AI)” mode — fixes grammar and paragraphs offline. Downloads once.")
            llmDownloadProgress.isHidden = true
            llmDownloadProgress.doubleValue = 0
        }

        downloadLLMModelButton.isHidden = downloaded
        downloadLLMModelButton.isEnabled = !isDownloadingModel && !downloaded
        downloadLLMModelButton.title = isDownloadingModel
            ? L.t("Скачивание…", "Downloading…")
            : L.t("Скачать (\(model.sizeLabel))", "Download (\(model.sizeLabel))")
    }

    /// Лёгкое обновление прогресса Whisper-модели — двигает только бар и подпись
    /// в карточке «Модель», без полного `render` (тот читает историю с диска).
    func updateWhisperDownloadProgress(fraction: Double, label: String) {
        downloadProgressIndicator.isHidden = false
        downloadProgressIndicator.doubleValue = fraction
        modelStatusLabel.stringValue = label
    }

    /// Лёгкое обновление прогресса модели «Красиво» — только бар и подпись в
    /// под-карточке, без полного `render`.
    func updateLLMDownloadProgress(fraction: Double, label: String) {
        llmDownloadProgress.isHidden = false
        llmDownloadProgress.doubleValue = fraction
        llmModelHint.stringValue = label
        downloadLLMModelButton.title = L.t("Скачивание…", "Downloading…")
        downloadLLMModelButton.isEnabled = false
    }

    // MARK: - Сборка контролов

    private func buildControls() {
        startButton = StyledButton(title: L.t("Записать", "Record"), style: .accent, action: #selector(startRecording), target: self)
        stopButton = StyledButton(title: L.t("Стоп и распознать", "Stop & transcribe"), style: .accent, action: #selector(stopAndTranscribe), target: self)
        cancelButton = StyledButton(title: L.t("Отмена", "Cancel"), style: .ghost, action: #selector(cancelRecording), target: self)
        testAudioButton = StyledButton(title: L.t("Тест аудио", "Test audio"), style: .ghost, action: #selector(transcribeTestAudio), target: self)
        downloadModelButton = StyledButton(title: L.t("Скачать модель", "Download model"), style: .accent, action: #selector(downloadSelectedModel), target: self)
        downloadLLMModelButton = StyledButton(title: L.t("Скачать модель «Умная (ИИ)»", "Download “Smart (AI)” model"), style: .accent, action: #selector(downloadLocalLLMModel), target: self)
        openModelsFolderButton = StyledButton(title: L.t("Папка моделей", "Models folder"), style: .secondary, action: #selector(openModelsFolder), target: self)
        setToggleHotkeyButton = StyledButton(title: L.t("Задать клавишу", "Set key"), style: .secondary, action: #selector(beginToggleHotkeyCapture), target: self)
        setPushToTalkHotkeyButton = StyledButton(title: L.t("Задать клавишу", "Set key"), style: .secondary, action: #selector(beginPushToTalkHotkeyCapture), target: self)
        applySettingsButton = StyledButton(title: L.t("Применить", "Apply"), style: .primary, action: #selector(applySettings), target: self)
        dictionaryEditor.onChange = { [weak self] entries in
            self?.delegate?.controlPanelDidSetDictionary(entries)
        }
        copyLastButton = StyledButton(title: L.t("Копировать последнее", "Copy latest"), style: .secondary, action: #selector(copyLast), target: self)
        openHistoryButton = StyledButton(title: L.t("Открыть файл", "Open file"), style: .ghost, action: #selector(openHistory), target: self)
        microphoneButton = StyledButton(title: L.t("Выдать доступ", "Grant access"), style: .secondary, action: #selector(openMicrophoneSettings), target: self)
        accessibilityButton = StyledButton(title: L.t("Выдать доступ", "Grant access"), style: .secondary, action: #selector(openAccessibilitySettings), target: self)
        checkForUpdatesButton = StyledButton(title: L.t("Проверить обновления", "Check for Updates"), style: .secondary, action: #selector(checkForUpdates), target: self)
        showDiagnosticsLogButton = StyledButton(title: L.t("Показать в Finder", "Show in Finder"), style: .secondary, action: #selector(showDiagnosticsLog), target: self)

        for popup in [modelPopup, polishLevelPopup] {
            popup.controlSize = .large
            popup.translatesAutoresizingMaskIntoConstraints = false
            popup.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }

        languageRow = SettingsDisclosureRow(
            title: L.t("Язык", "Language"),
            subtitle: L.t("Распознаваемый язык речи", "Spoken language to recognize")
        ) { [weak self] in self?.presentLanguagePicker() }

        microphoneRow = SettingsDisclosureRow(
            title: L.t("Микрофон", "Microphone"),
            subtitle: L.t("Устройство ввода для записи", "Input device used for recording")
        ) { [weak self] in self?.presentMicrophonePicker() }

        interfaceLanguageRow = SettingsDisclosureRow(
            title: L.t("Язык интерфейса", "Interface language"),
            subtitle: L.t("Язык приложения", "Application language")
        ) { [weak self] in self?.presentInterfaceLanguagePicker() }

        autoPasteToggle = SettingsToggleRow(
            title: L.t("Автовставка", "Auto-paste"),
            subtitle: L.t("Сразу вставлять текст в активное поле (нужен доступ Accessibility)",
                          "Paste text into the active field right away (needs Accessibility access)")
        ) { [weak self] on in self?.delegate?.controlPanelDidSetAutoPaste(on) }

        removeFillersToggle = SettingsToggleRow(
            title: L.t("Убирать слова-паразиты", "Remove filler words"),
            subtitle: L.t("Эээ, ну, как бы, типа, короче…", "Um, uh, like, you know…")
        ) { [weak self] on in self?.delegate?.controlPanelDidSetRemoveFillers(on) }

        smartContextToggle = SettingsToggleRow(
            title: L.t("Умный контекст", "Smart context"),
            subtitle: L.t(
                "Понимает активное поле: поиск, письмо, код, URL или пароль. Использует Accessibility и короткие локальные подсказки; пароли не сохраняются.",
                "Understands the active field: search, email, code, URL, or password. Uses Accessibility and short local hints; passwords are never stored."
            )
        ) { [weak self] on in self?.delegate?.controlPanelDidSetSmartContext(on) }

        launchAtLoginToggle = SettingsToggleRow(
            title: L.t("Запускать при входе в систему", "Launch at login"),
            subtitle: L.t("Lyra Voice стартует автоматически после входа в macOS",
                          "Lyra Voice starts automatically after you log in to macOS")
        ) { [weak self] on in self?.delegate?.controlPanelDidSetLaunchAtLogin(on) }

        showInDockToggle = SettingsToggleRow(
            title: L.t("Показывать в Dock", "Show in Dock"),
            subtitle: L.t("Иконка в Dock. Выключите — приложение живёт только в строке меню",
                          "Dock icon. Turn off to keep the app in the menu bar only")
        ) { [weak self] on in self?.delegate?.controlPanelDidSetShowInDock(on) }

        playSoundsToggle = SettingsToggleRow(
            title: L.t("Звук уведомления", "Notification sound"),
            subtitle: L.t("Тихие сигналы старта, остановки и отмены записи",
                          "Soft cues for recording start, stop and cancel")
        ) { [weak self] on in self?.delegate?.controlPanelDidSetPlaySounds(on) }

        saveRecordingsToggle = SettingsToggleRow(
            title: L.t("Сохранять записи для улучшения", "Keep recordings to improve"),
            subtitle: L.t("Звук диктовок остаётся на этом Mac (папка Recordings) для настройки распознавания. Никуда не отправляется. По умолчанию выключено.",
                          "Dictation audio stays on this Mac (Recordings folder) to tune recognition. Never uploaded. Off by default.")
        ) { [weak self] on in
            self?.delegate?.controlPanelDidSetSaveRecordings(on)
            self?.recordingsRetentionRow?.isHidden = !on
        }

        recordingsRetentionRow = SettingsDisclosureRow(
            title: L.t("Хранить записи", "Keep recordings for"),
            subtitle: L.t("Старые записи будут удаляться автоматически", "Old recordings are deleted automatically")
        ) { [weak self] in self?.presentRecordingsRetentionPicker() }

        automaticUpdatesToggle = SettingsToggleRow(
            title: L.t("Автоматически проверять обновления", "Automatically check for updates"),
            subtitle: L.t("Lyra Voice будет напоминать о новых версиях", "Lyra Voice will notify you about new versions")
        ) { [weak self] on in self?.delegate?.controlPanelDidSetAutomaticallyCheckForUpdates(on) }

        diagnosticsLoggingToggle = SettingsToggleRow(
            title: L.t("Записывать диагностический лог", "Write diagnostics log"),
            subtitle: L.t("Помогает разобраться в проблемах — хранится только на этом Mac",
                          "Helps troubleshoot issues — stored only on this Mac")
        ) { [weak self] on in self?.delegate?.controlPanelDidSetDiagnosticsLogging(on) }

        // VAD (обрезка пауз) и нормализация громкости — внутренняя предобработка аудио,
        // всегда включены по умолчанию (vadEnabled / audioNormalizationEnabled).
        // Намеренно не выносятся в UI: это инженерная кухня, а не пользовательский выбор.

        autoEnterToggle = SettingsToggleRow(
            title: L.t("Enter после вставки", "Enter after paste"),
            subtitle: L.t("Нажимает Enter сразу после вставки — удобно для чатов и мессенджеров.",
                          "Presses Enter right after pasting — handy for chats and messengers.")
        ) { [weak self] on in self?.delegate?.controlPanelDidSetAutoEnterAfterPaste(on) }

        simulateTypingToggle = SettingsToggleRow(
            title: L.t("Симулировать нажатия клавиш", "Simulate keypresses"),
            subtitle: L.t("Вводит символы по одному вместо Cmd+V — для Terminal и полей без вставки.",
                          "Types characters one by one instead of Cmd+V — for Terminal and non-paste fields.")
        ) { [weak self] on in
            self?.delegate?.controlPanelDidSetPasteMode(on ? .simulateTyping : .clipboard)
        }

        overlayModeRow = SettingsDisclosureRow(
            title: L.t("Оверлей записи", "Recording overlay"),
            subtitle: L.t("Отображение во время диктовки", "Display mode while recording")
        ) { [weak self] in self?.presentOverlayModePicker() }

        transcriptionProviderSelector.configure(options: [
            SelectionOption(id: TranscriptionProvider.local.rawValue,
                            title: L.t("Локально", "Local"),
                            subtitle: L.t("whisper.cpp на этом Mac, приватно и офлайн", "whisper.cpp on this Mac, private and offline")),
            SelectionOption(id: TranscriptionProvider.openAI.rawValue,
                            title: L.t("OpenAI", "OpenAI"),
                            subtitle: L.t("gpt-4o-transcribe / whisper-1 — лучшее качество, аудио уходит на серверы OpenAI",
                                          "gpt-4o-transcribe / whisper-1 — best quality, audio sent to OpenAI servers"))
        ]) { [weak self] id in
            guard let self, let provider = TranscriptionProvider(rawValue: id) else { return }
            self.openAIFieldsContainer?.isHidden = provider != .openAI
            self.localModelCard?.isHidden = provider == .openAI
            self.delegate?.controlPanelDidSetTranscriptionProvider(provider)
        }

        openAIKeyField.placeholderString = "sk-…"
        openAIKeyField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        openAIKeyField.wantsLayer = true
        openAIKeyField.layer?.cornerRadius = 8
        openAIKeyField.translatesAutoresizingMaskIntoConstraints = false
        openAIKeyField.action = #selector(openAIKeyChanged)
        openAIKeyField.target = self

        openAIModelRow = SettingsDisclosureRow(
            title: L.t("Модель OpenAI", "OpenAI model"),
            subtitle: OpenAITranscriptionModel.gpt4oTranscribe.displayName
        ) { [weak self] in self?.showOpenAIModelPicker() }

        polishLevelSelector.configure(options: [
            SelectionOption(id: PolishLevel.rules.rawValue, title: L.t("Быстрая", "Fast"), subtitle: L.t("Пунктуация и паразиты — мгновенно, без ИИ", "Punctuation and filler words — instant, no AI")),
            SelectionOption(id: PolishLevel.localLLM.rawValue, title: L.t("Умная (ИИ)", "Smart (AI)"), subtitle: L.t("Локальный ИИ (Qwen 3B) чинит грамматику и стиль — на 1–2 сек дольше", "Local AI (Qwen 3B) fixes grammar and style — adds 1–2 sec")),
            SelectionOption(id: PolishLevel.cloud.rawValue, title: L.t("Облачная (ИИ)", "Cloud (AI)"), subtitle: L.t("Лучшее качество через API — нужен ключ", "Best quality via API — requires a key"))
        ]) { [weak self] id in
            guard let level = PolishLevel(rawValue: id) else { return }
            self?.delegate?.controlPanelDidSetPolishLevel(level)
        }

        mediaInterruptionSelector.configure(options: [
            SelectionOption(id: MediaInterruptionMode.none.rawValue, title: L.t("Не трогать", "Leave alone"), subtitle: L.t("Оставить музыку и видео как есть", "Keep music and video as is")),
            SelectionOption(id: MediaInterruptionMode.pause.rawValue, title: L.t("Пауза", "Pause"), subtitle: L.t("Music и Spotify — на паузу, остальной звук — приглушить", "Pause Music and Spotify, duck everything else")),
            SelectionOption(id: MediaInterruptionMode.duck.rawValue, title: L.t("Приглушить", "Duck"), subtitle: L.t("Снизить громкость системы на запись", "Lower system volume while recording"))
        ]) { [weak self] id in
            guard let mode = MediaInterruptionMode(rawValue: id) else { return }
            self?.delegate?.controlPanelDidSetMediaInterruptionMode(mode)
        }
    }

    // MARK: - Лейаут: sidebar + контент

    private func buildLayout() {
        let sidebar = makeSidebar()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sidebar)

        // Плотная НЕпрозрачная подложка под областью контента (заподлицо с сайдбаром,
        // без шва-разделителя): карточки на ровном фоне, сайдбар остаётся стеклом.
        let contentBackdrop = NSView()
        contentBackdrop.translatesAutoresizingMaskIntoConstraints = false
        contentBackdrop.wantsLayer = true
        contentBackdrop.layer?.backgroundColor = DS.Color.base.cgColor
        contentBackdrop.layer?.isOpaque = true
        addSubview(contentBackdrop)

        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.drawsBackground = false
        contentScroll.hasVerticalScroller = true
        contentScroll.autohidesScrollers = true
        contentScroll.borderType = .noBorder
        contentScroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        addSubview(contentScroll)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 222),

            contentBackdrop.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentBackdrop.topAnchor.constraint(equalTo: topAnchor),
            contentBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentScroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentScroll.topAnchor.constraint(equalTo: topAnchor),
            contentScroll.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        pages = [
            .home: makeHomePage(),
            .modes: makePage(.modes, cards: [makeHotkeyCard()]),
            .vocabulary: makePage(.vocabulary, cards: [makeVocabularyCard()]),
            .models: makePage(.models, cards: [makePolishCard(), makeTranscriptionProviderCard(), localModelCardView(), makeRecognitionCard()]),
            .sound: makePage(.sound, cards: [makeSoundCard()]),
            .system: makePage(.system, cards: [makeTextInputCard(), makeInterfaceCard(), makeContextPrivacyCard(), makeAppBehaviorCard(), makePermissionsCard(), makeUpdatesCard(), makeDiagnosticsCard()]),
            .history: makeHistoryPage()
        ]
    }

    private func makeSidebar() -> NSView {
        // Liquid Glass подложка остаётся только у фона сайдбара. Сами пункты меню —
        // плоские и утилитарные, ближе к reference shell.
        let panel = SidebarPanelView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)

        // Заголовок приложения сверху.
        let appTitle = NSTextField(labelWithString: AppBrand.displayName)
        appTitle.font = DS.Font.display(17, weight: .bold)
        appTitle.textColor = DS.Color.textPrimary
        let appSub = NSTextField(labelWithString: L.t("Локальная диктовка", "Local dictation"))
        appSub.font = DS.Font.text(11)
        appSub.textColor = DS.Color.textTertiary
        let titleBox = NSStackView(views: [appTitle, appSub])
        titleBox.orientation = .vertical
        titleBox.alignment = .leading
        titleBox.spacing = 1
        titleBox.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        let brandHeader = NSStackView(views: [makeBrandLogoView(size: 34), titleBox])
        brandHeader.orientation = .horizontal
        brandHeader.alignment = .centerY
        brandHeader.spacing = 9
        brandHeader.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        stack.addArrangedSubview(spacer(height: 38))
        stack.addArrangedSubview(brandHeader)
        stack.addArrangedSubview(spacer(height: 14))

        // Заголовки секций и групповые отступы убраны — все пункты с равным шагом.
        for section in PanelSection.allCases {
            let item = SidebarItem(section: section) { [weak self] in self?.select(section) }
            sidebarItems[section] = item
            stack.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        }

        panel.addSubview(stack)
        var constraints = [
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            stack.topAnchor.constraint(equalTo: panel.topAnchor)
        ]

        if showsSidebarFutureSlots {
            let bottomStack = NSStackView(views: [makeUpgradeCard(), makeAccountRow()])
            bottomStack.orientation = .vertical
            bottomStack.alignment = .width
            bottomStack.spacing = 10
            bottomStack.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(bottomStack)
            constraints.append(contentsOf: [
                stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomStack.topAnchor, constant: -18),
                bottomStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
                bottomStack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
                bottomStack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -20)
            ])
        } else {
            constraints.append(stack.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -20))
        }
        NSLayoutConstraint.activate(constraints)
        return panel
    }

    private func makeUpgradeCard() -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        card.layer?.cornerRadius = 12
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        icon.contentTintColor = DS.Color.textPrimary
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L.t("Boost with AI", "Boost with AI"))
        title.font = DS.Font.text(12, weight: .semibold)
        title.textColor = DS.Color.textPrimary
        let body = NSTextField(wrappingLabelWithString: L.t(
            "Облачная полировка, быстрые модели и Pro-функции.",
            "Cloud polish, faster models, and Pro features."
        ))
        body.font = DS.Font.text(10)
        body.textColor = DS.Color.textTertiary
        body.maximumNumberOfLines = 2

        let upgradeButton = StyledButton(
            title: L.t("Upgrade to Pro", "Upgrade to Pro"),
            style: .accent,
            action: nil,
            target: nil
        )

        let textStack = NSStackView(views: [title, body])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        let heading = NSStackView(views: [icon, textStack])
        heading.orientation = .horizontal
        heading.alignment = .top
        heading.spacing = 8

        let stack = NSStackView(views: [heading, upgradeButton])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 122),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 13),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -13),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return card
    }

    private func makeAccountRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.14).cgColor
        row.layer?.cornerRadius = 11
        row.layer?.cornerCurve = .continuous
        row.layer?.borderWidth = 1
        row.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        let avatar = NSTextField(labelWithString: "LV")
        avatar.alignment = .center
        avatar.font = DS.Font.text(10, weight: .semibold)
        avatar.textColor = DS.Color.textPrimary
        avatar.wantsLayer = true
        avatar.layer?.backgroundColor = DS.Color.surfaceSunken.cgColor
        avatar.layer?.cornerRadius = 8
        avatar.layer?.cornerCurve = .continuous
        avatar.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L.t("Аккаунт", "Account"))
        title.font = DS.Font.text(12, weight: .semibold)
        title.textColor = DS.Color.textPrimary
        let subtitle = NSTextField(labelWithString: L.t("Локальный профиль", "Local profile"))
        subtitle.font = DS.Font.text(10)
        subtitle.textColor = DS.Color.textTertiary
        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        chevron.contentTintColor = DS.Color.textTertiary
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [avatar, textStack, NSView(), chevron])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 9
        content.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(content)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 58),
            avatar.widthAnchor.constraint(equalToConstant: 32),
            avatar.heightAnchor.constraint(equalToConstant: 32),
            chevron.widthAnchor.constraint(equalToConstant: 16),
            content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 11),
            content.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10)
        ])
        return row
    }

    private func makeBrandLogoView(size: CGFloat) -> NSImageView {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = BrandAssets.logoImage(size: size)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: size),
            imageView.heightAnchor.constraint(equalToConstant: size)
        ])
        return imageView
    }

    private func spacer(height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    /// Лёгкая вложенная под-панель внутри карточки (тоньше и темнее основного
    /// стекла) — для группировки родственных контролов, напр. модели «Красиво».
    private func makeInsetPanel(spacing: CGFloat = 10, _ build: (NSStackView) -> Void) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = DS.Color.surfaceSunken.cgColor
        container.layer?.cornerRadius = 9
        container.layer?.cornerCurve = .continuous
        container.layer?.borderWidth = 1
        container.layer?.borderColor = DS.Color.surfaceBorder.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        build(stack)
        return container
    }

    private func select(_ section: PanelSection) {
        currentSection = section
        for (key, item) in sidebarItems { item.isSelected = (key == section) }
        // История могла обновиться, пока раздел был скрыт — достраиваем сейчас.
        if section == .history, historyNeedsRender { performHistoryRender() }

        guard let page = pages[section] else { return }
        if let old = contentWidthConstraint { old.isActive = false }
        if let old = contentHeightConstraint { old.isActive = false; contentHeightConstraint = nil }
        contentScroll.documentView = page
        if let clip = contentScroll.contentView as NSClipView? {
            let constraint = page.widthAnchor.constraint(equalTo: clip.widthAnchor)
            constraint.isActive = true
            contentWidthConstraint = constraint
            page.leadingAnchor.constraint(equalTo: clip.leadingAnchor).isActive = true
            page.topAnchor.constraint(equalTo: clip.topAnchor).isActive = true
            // Все страницы (включая Home) скроллятся внешним contentScroll —
            // высоту НЕ фиксируем, иначе вложенный контент схлопывается.
            if false {
                let height = page.heightAnchor.constraint(equalTo: clip.heightAnchor)
                height.isActive = true
                contentHeightConstraint = height
            }
        }
        // Прокрутка к верху ПОСЛЕ лейаута — иначе flipped-документ открывается
        // прокрученным вниз (дашборд уезжает выше footer).
        layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.contentScroll.contentView.scroll(to: .zero)
            self.contentScroll.reflectScrolledClipView(self.contentScroll.contentView)
        }
    }

    // MARK: - Страница и карточки

    private func makePage(_ section: PanelSection, cards: [NSView]) -> NSView {
        let page = FlippedView()
        page.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: section.title)
        header.font = DS.Font.display(20, weight: .semibold)
        header.textColor = DS.Color.textPrimary
        let sub = NSTextField(labelWithString: section.subtitle)
        sub.font = DS.Font.text(13)
        sub.textColor = DS.Color.textSecondary

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 16   // воздух между блоками-карточками
        stack.translatesAutoresizingMaskIntoConstraints = false
        let headerRow = leftAligned(header)
        let subRow = leftAligned(sub)
        stack.addArrangedSubview(headerRow)
        stack.addArrangedSubview(subRow)
        stack.setCustomSpacing(3, after: headerRow)
        stack.setCustomSpacing(26, after: subRow)   // больше отступ от описания до блоков
        for card in cards {
            stack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: 38),
            stack.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -28)
        ])
        return page
    }

    /// Карточка-обёртка с внутренним вертикальным стеком и крупным паддингом.
    private func makeCard(spacing: CGFloat = 10, _ build: (NSStackView) -> Void) -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        build(stack)
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return card
    }

    // MARK: - Home: одна колонка — дашборд сверху, история снизу (скроллится внешним contentScroll)

    private func makeHomePage() -> NSView {
        // Конфигурация лейблов.
        greetingTitleLabel.font = DS.Font.heading(26, weight: .bold)
        greetingTitleLabel.textColor = DS.Color.textPrimary
        greetingTitleLabel.maximumNumberOfLines = 1
        greetingDetailLabel.font = DS.Font.text(13)
        greetingDetailLabel.textColor = DS.Color.textSecondary
        greetingDetailLabel.maximumNumberOfLines = 2

        statusTitleLabel.font = DS.Font.heading(16, weight: .semibold)
        statusTitleLabel.textColor = DS.Color.textPrimary
        statusTitleLabel.alignment = .left
        statusDetailLabel.font = DS.Font.text(12)
        statusDetailLabel.textColor = DS.Color.textSecondary
        statusDetailLabel.alignment = .left
        statusDetailLabel.maximumNumberOfLines = 2

        // Метрики.
        let statsRow = NSStackView(views: [
            makeMetricTile(title: L.t("Всего диктовок", "Total dictations"), valueLabel: dictationCountLabel),
            makeMetricTile(title: L.t("Всего слов", "Total words"), valueLabel: wordCountLabel),
            makeMetricTile(title: L.t("Голос всего", "Total voice"), valueLabel: durationLabel)
        ])
        statsRow.orientation = .horizontal
        statsRow.spacing = 12
        statsRow.distribution = .fillEqually

        let usageCard = makeUsageActivityCard()

        // Быстрые действия (как «Get started» у SuperWhisper): горячие клавиши,
        // модель распознавания, словарь — по клику переключают раздел сайдбара.
        let quickActionsRow = NSStackView(views: [
            makeQuickActionTile(
                icon: "keyboard",
                title: L.t("Горячие клавиши", "Shortcuts"),
                subtitle: L.t("Настроить хоткеи", "Customize your shortcuts")
            ) { [weak self] in self?.select(.modes) },
            makeQuickActionTile(
                icon: "cpu",
                title: L.t("Модель", "Model"),
                subtitle: L.t("Выбрать модель распознавания", "Choose a recognition model")
            ) { [weak self] in self?.select(.models) },
            makeQuickActionTile(
                icon: "book",
                title: L.t("Словарь", "Vocabulary"),
                subtitle: L.t("Добавить слово или имя", "Add a word or name")
            ) { [weak self] in self?.select(.vocabulary) }
        ])
        quickActionsRow.orientation = .horizontal
        quickActionsRow.spacing = 12
        quickActionsRow.distribution = .fillEqually

        // Карточка статуса + записи.
        let statusBox = NSStackView(views: [statusTitleLabel, statusDetailLabel])
        statusBox.orientation = .vertical
        statusBox.alignment = .leading
        statusBox.spacing = 3
        let recordRow = NSStackView(views: [startButton, stopButton])
        recordRow.orientation = .horizontal
        recordRow.spacing = 10
        recordRow.distribution = .fillEqually
        let recordRow2 = NSStackView(views: [cancelButton, testAudioButton])
        recordRow2.orientation = .horizontal
        recordRow2.spacing = 10
        recordRow2.distribution = .fillEqually

        let card = GlassCardView()   // C-редизайн: карточка статуса на стекле
        card.translatesAutoresizingMaskIntoConstraints = false
        let cardStack = NSStackView(views: [statusBox, recordRow, recordRow2])
        cardStack.orientation = .vertical
        cardStack.alignment = .width
        cardStack.spacing = 12
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        // Явная ширина строк внутри карточки — иначе статус центрируется,
        // а ряды кнопок хагуют контент (то же, что и в колонке).
        for view in [statusBox, recordRow, recordRow2] as [NSView] {
            view.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
        }

        let column = NSStackView(views: [
            leftAligned(greetingTitleLabel),
            leftAligned(greetingDetailLabel),
            quickActionsRow,
            statsRow,
            usageCard,
            card
        ])
        column.orientation = .vertical
        column.alignment = .width
        column.distribution = .fill
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false
        column.setCustomSpacing(6, after: column.arrangedSubviews[0])
        column.setCustomSpacing(26, after: column.arrangedSubviews[1])

        for view in [quickActionsRow, statsRow, usageCard, card] as [NSView] {
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }

        let page = FlippedView()
        page.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 36),
            column.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -36),
            column.topAnchor.constraint(equalTo: page.topAnchor, constant: 40),
            column.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -36)
        ])
        return page
    }

    // MARK: - История (отдельная вкладка)

    private func makeHistoryPage() -> NSView {
        historySearchField.placeholderString = L.t("Поиск в истории…", "Search history…")
        historySearchField.font = DS.Font.text(14)
        historySearchField.controlSize = .large
        historySearchField.translatesAutoresizingMaskIntoConstraints = false
        historySearchField.heightAnchor.constraint(equalToConstant: 38).isActive = true
        historySearchField.target = self
        historySearchField.action = #selector(historySearchChanged)
        historySearchField.sendsWholeSearchString = false
        historySearchField.sendsSearchStringImmediately = true

        homeHistoryStack.orientation = .vertical
        homeHistoryStack.alignment = .leading
        homeHistoryStack.distribution = .fill
        homeHistoryStack.spacing = 8
        homeHistoryStack.translatesAutoresizingMaskIntoConstraints = false

        let headerLabel = NSTextField(labelWithString: PanelSection.history.title)
        headerLabel.font = DS.Font.display(20, weight: .semibold)
        headerLabel.textColor = DS.Color.textPrimary
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let subLabel = NSTextField(labelWithString: PanelSection.history.subtitle)
        subLabel.font = DS.Font.text(13)
        subLabel.textColor = DS.Color.textSecondary

        // Кнопка ⋯ — раскрывает меню с деструктивными/сервисными действиями.
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let menuImage = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
            .flatMap { $0.withSymbolConfiguration(symbolConfig) }
        let menuBtn = NSButton(frame: .zero)
        menuBtn.image = menuImage
        menuBtn.isBordered = false
        menuBtn.contentTintColor = DS.Color.textTertiary
        menuBtn.target = self
        menuBtn.action = #selector(showHistoryActionsMenu(_:))
        menuBtn.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = NSView()
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.addSubview(headerLabel)
        titleRow.addSubview(menuBtn)
        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            headerLabel.centerYAnchor.constraint(equalTo: titleRow.centerYAnchor),
            menuBtn.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),
            menuBtn.centerYAnchor.constraint(equalTo: titleRow.centerYAnchor),
            titleRow.heightAnchor.constraint(equalToConstant: 34)
        ])

        let actionsRow = NSStackView(views: [copyLastButton, openHistoryButton])
        actionsRow.orientation = .horizontal
        actionsRow.spacing = 10
        actionsRow.distribution = .fillEqually

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleRow)
        stack.addArrangedSubview(leftAligned(subLabel))
        stack.addArrangedSubview(actionsRow)
        stack.addArrangedSubview(historySearchField)
        stack.addArrangedSubview(homeHistoryStack)
        stack.setCustomSpacing(3, after: titleRow)
        stack.setCustomSpacing(22, after: stack.arrangedSubviews[1])
        stack.setCustomSpacing(10, after: actionsRow)
        stack.setCustomSpacing(10, after: historySearchField)

        for view in [titleRow, actionsRow, historySearchField, homeHistoryStack] as [NSView] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let page = FlippedView()
        page.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: 38),
            stack.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -28)
        ])
        return page
    }

    @objc private func showHistoryActionsMenu(_ sender: NSButton) {
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: L.t("Копировать последнее", "Copy latest"),
                                  action: #selector(copyLast), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let openItem = NSMenuItem(title: L.t("Открыть файл истории", "Open history file"),
                                  action: #selector(openHistory), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem()
        clearItem.action = #selector(clearHistory)
        clearItem.target = self
        clearItem.attributedTitle = NSAttributedString(
            string: L.t("Очистить всё", "Clear all"),
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        menu.addItem(clearItem)

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.height + 4),
                   in: sender)
    }

    /// Оборачивает карточку локальных моделей и запоминает ссылку, чтобы скрывать её
    /// при выборе облачного провайдера.
    private func localModelCardView() -> NSView {
        let card = makeModelCard()
        localModelCard = card
        return card
    }

    private func makeModelCard() -> NSView {
        makeCard { stack in
            // Короткое пояснение, что выбирается в этом разделе.
            let intro = NSTextField(wrappingLabelWithString: L.t(
                "Распознавание речи в текст идёт локально на этом Mac. Точнее модель — крупнее файл и медленнее; быстрее — легче. Выберите и скачайте.",
                "Speech-to-text runs locally on this Mac. More accurate means a bigger, slower file; faster means lighter. Pick one and download."))
            intro.font = DS.Font.text(12)
            intro.textColor = DS.Color.textTertiary

            // Описание выбранной модели — показывается под списком ровно один раз.
            modelComparisonLabel.font = DS.Font.text(12)
            modelComparisonLabel.textColor = DS.Color.textSecondary
            modelComparisonLabel.maximumNumberOfLines = 3
            // Короткий статус-действие (готова / скачать / прогресс).
            modelStatusLabel.font = DS.Font.text(12, weight: .semibold)
            modelStatusLabel.textColor = DS.Color.textSecondary
            downloadProgressIndicator.isIndeterminate = false
            downloadProgressIndicator.minValue = 0
            downloadProgressIndicator.maxValue = 1
            downloadProgressIndicator.doubleValue = 0
            downloadProgressIndicator.controlSize = .regular

            let modelList = NSStackView()
            modelList.orientation = .vertical
            modelList.alignment = .width
            modelList.spacing = 10
            modelList.translatesAutoresizingMaskIntoConstraints = false
            for profile in ModelProfile.builtInProfiles {
                let option = ModelOptionView(profile: profile) { [weak self] id in
                    self?.delegate?.controlPanelDidSelectModel(id: id)
                }
                modelOptionViews[profile.id] = option
                modelList.addArrangedSubview(option)
                option.widthAnchor.constraint(equalTo: modelList.widthAnchor).isActive = true
            }

            let buttons = NSStackView(views: [downloadModelButton, openModelsFolderButton, NSView()])
            buttons.orientation = .horizontal
            buttons.spacing = 12

            stack.addArrangedSubview(intro)
            stack.setCustomSpacing(16, after: intro)
            stack.addArrangedSubview(modelList)
            stack.addArrangedSubview(modelComparisonLabel)
            stack.setCustomSpacing(6, after: modelComparisonLabel)
            stack.addArrangedSubview(modelStatusLabel)
            stack.addArrangedSubview(downloadProgressIndicator)
            stack.addArrangedSubview(buttons)
        }
    }

    private func makeHotkeyCard() -> NSView {
        makeCard(spacing: 16) { stack in
            let caption = NSTextField(labelWithString: L.t("Доступны одновременно", "Available at the same time"))
            caption.font = DS.Font.text(11, weight: .semibold)
            caption.textColor = DS.Color.textTertiary

            let toggleRow = makeHotkeyActionRow(
                title: L.t("Старт / Стоп", "Start / Stop"),
                subtitle: L.t("Нажал — запись началась. Нажал ещё раз — стоп и вставка.",
                              "Press once to start. Press again to stop and paste."),
                label: toggleHotkeyLabel,
                button: setToggleHotkeyButton
            )

            let holdRow = makeHotkeyActionRow(
                title: L.t("Зажать для диктовки", "Hold to dictate"),
                subtitle: L.t("Держишь клавишу — идёт запись. Отпустил — стоп и вставка.",
                              "Hold the key to record. Release to stop and paste."),
                label: pushToTalkHotkeyLabel,
                button: setPushToTalkHotkeyButton
            )

            let hint = NSTextField(wrappingLabelWithString: L.t(
                "Fn можно назначить только на одно действие. Если клавиша уже занята вторым действием, приложение не сохранит конфликт.",
                "Fn can be assigned to one action only. If a key is already used by the other action, the app will not save the conflict."))
            hint.font = DS.Font.text(11)
            hint.textColor = DS.Color.textTertiary
            hint.maximumNumberOfLines = 2

            stack.addArrangedSubview(leftAligned(caption))
            stack.addArrangedSubview(toggleRow)
            toggleRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.addArrangedSubview(holdRow)
            holdRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.setCustomSpacing(14, after: holdRow)
            stack.addArrangedSubview(leftAligned(hint))
        }
    }

    private func makeHotkeyActionRow(title: String, subtitle: String, label: NSTextField, button: StyledButton) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = DS.Font.text(14, weight: .semibold)
        titleLabel.textColor = DS.Color.textPrimary

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = DS.Font.text(12)
        subtitleLabel.textColor = DS.Color.textSecondary
        subtitleLabel.maximumNumberOfLines = 2

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        label.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = DS.Color.textPrimary
        label.alignment = .center
        label.wantsLayer = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let chip = NSView()
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.wantsLayer = true
        chip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        chip.layer?.cornerRadius = 9
        chip.layer?.cornerCurve = .continuous
        chip.layer?.borderWidth = 1
        chip.layer?.borderColor = DS.Color.accent.withAlphaComponent(0.55).cgColor
        chip.setContentHuggingPriority(.required, for: .horizontal)
        chip.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: chip.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -7),
            chip.widthAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])

        let row = NSStackView(views: [textStack, NSView(), chip, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func makeRecognitionCard() -> NSView {
        // Технические пути (whisper-cli, папка моделей) намеренно НЕ показываем:
        // они определяются автоматически. Поля остаются скрытыми источниками —
        // `renderSettings` их наполняет, `applySettings` читает.
        makeCard { stack in
            configureTextField(promptField)
            promptField.heightAnchor.constraint(equalToConstant: 72).isActive = true

            // Язык
            stack.addArrangedSubview(languageRow)

            // Промпт-подсказка: короткая подпись на виду, подробности — в tooltip (ⓘ).
            let promptColumn = labeledColumn(
                label: L.t("Промпт-подсказка", "Prompt hint"),
                tooltip: L.t(
                    "Необязательно. Перечислите имена, термины и бренды, которые часто диктуете (напр. «Lyra Voice, whisper.cpp, КБЖУ») — модель будет реже их искажать. На стиль и формулировки текста не влияет.",
                    "Optional. List names, terms and brands you dictate often (e.g. “Lyra Voice, whisper.cpp”) so the model misrecognizes them less. It does not change writing style or phrasing."),
                control: promptField)
            stack.addArrangedSubview(promptColumn)
            let promptHint = NSTextField(labelWithString: L.t(
                "Имена и термины для точного распознавания",
                "Names and terms for accurate recognition"))
            promptHint.font = DS.Font.text(11)
            promptHint.textColor = DS.Color.textTertiary
            stack.addArrangedSubview(promptHint)
            stack.setCustomSpacing(5, after: promptColumn)

            stack.addArrangedSubview(leftAligned(applySettingsButton))
            stack.setCustomSpacing(14, after: promptHint)
        }
    }

    private func makePolishCard() -> NSView {
        makeCard { stack in
            stack.addArrangedSubview(labeledColumn(label: L.t("Уровень полировки", "Polish level"), control: polishLevelSelector))

            // Подсказка для «Облачная (ИИ)»: режим пока не реализован, чтобы выбор
            // не выглядел «ничего не происходит» — поясняем текущее поведение.
            cloudPolishHint.font = DS.Font.text(12)
            cloudPolishHint.textColor = DS.Color.textSecondary
            cloudPolishHint.stringValue = L.t(
                "Облачная полировка пока в разработке — сейчас применяются обычные правила («Быстрая»). Облачная транскрибация уже доступна в карточке «Транскрибация» ниже.",
                "Cloud polish is still in development — for now, regular rules (“Fast”) are applied. Cloud transcription is already available in the “Transcription” card below.")
            let cloudPolishPanel = makeInsetPanel { p in p.addArrangedSubview(cloudPolishHint) }
            cloudPolishPanel.isHidden = true
            self.cloudPolishPanel = cloudPolishPanel
            stack.addArrangedSubview(cloudPolishPanel)

            // Под-карточка модели «Красиво»: имя + размер/«Готово», статус,
            // прогресс-бар (виден только при скачивании) и кнопка загрузки.
            llmModelNameLabel.font = DS.Font.text(13, weight: .semibold)
            llmModelNameLabel.textColor = DS.Color.textPrimary

            llmSizeBadge.font = DS.Font.mono(10, weight: .medium)
            llmSizeBadge.textColor = DS.Color.textTertiary
            llmSizeBadge.setContentHuggingPriority(.required, for: .horizontal)

            llmReadyBadge.font = DS.Font.text(11, weight: .semibold)
            llmReadyBadge.textColor = DS.Color.success
            llmReadyBadge.stringValue = L.t("✓ Готово", "✓ Ready")
            llmReadyBadge.setContentHuggingPriority(.required, for: .horizontal)
            llmReadyBadge.isHidden = true

            let headerRow = NSStackView(views: [llmModelNameLabel, NSView(), llmSizeBadge, llmReadyBadge])
            headerRow.orientation = .horizontal
            headerRow.spacing = 8

            llmModelHint.font = DS.Font.text(12)
            llmModelHint.textColor = DS.Color.textSecondary

            llmDownloadProgress.isIndeterminate = false
            llmDownloadProgress.minValue = 0
            llmDownloadProgress.maxValue = 1
            llmDownloadProgress.doubleValue = 0
            llmDownloadProgress.controlSize = .regular
            llmDownloadProgress.isHidden = true

            let llmPanel = makeInsetPanel { p in
                p.addArrangedSubview(headerRow)
                headerRow.widthAnchor.constraint(equalTo: p.widthAnchor).isActive = true
                p.addArrangedSubview(llmModelHint)
                p.addArrangedSubview(llmDownloadProgress)
                llmDownloadProgress.widthAnchor.constraint(equalTo: p.widthAnchor).isActive = true
                p.addArrangedSubview(leftAligned(downloadLLMModelButton))
            }
            stack.addArrangedSubview(llmPanel)
            stack.addArrangedSubview(spacer(height: 6))

            stack.addArrangedSubview(removeFillersToggle)
        }
    }

    private func makeVocabularyCard() -> NSView {
        makeCard(spacing: 14) { stack in
            let dictionaryHint = NSTextField(wrappingLabelWithString: L.t(
                "Замены применяются после распознавания: что скажете слева — вставится справа. Удобно для терминов, имён и брендов (например, «джипити» → «GPT»).",
                "Replacements apply after recognition: what you say on the left gets inserted on the right. Handy for terms, names and brands (e.g. “jeepeetee” → “GPT”)."))
            dictionaryHint.font = DS.Font.text(12)
            dictionaryHint.textColor = DS.Color.textSecondary

            stack.addArrangedSubview(leftAligned(dictionaryHint))
            stack.addArrangedSubview(dictionaryEditor)
            dictionaryEditor.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            let keysHint = NSTextField(labelWithString: L.t(
                "Введите слово и замену → «Добавить» или Enter. Наведите на строку и нажмите ✕, чтобы удалить.",
                "Type a word and its replacement → “Add” or Enter. Hover a row and click ✕ to remove."))
            keysHint.font = DS.Font.text(11)
            keysHint.textColor = DS.Color.textTertiary
            stack.addArrangedSubview(leftAligned(keysHint))
        }
    }

    private func makeSoundCard() -> NSView {
        makeCard(spacing: 10) { stack in
            stack.addArrangedSubview(microphoneRow)
            microphoneRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.addArrangedSubview(spacer(height: 4))
            stack.addArrangedSubview(labeledColumn(label: L.t("Медиа во время записи", "Media while recording"), control: mediaInterruptionSelector))
            stack.addArrangedSubview(spacer(height: 4))
            stack.addArrangedSubview(playSoundsToggle)
            playSoundsToggle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func makeTextInputCard() -> NSView {
        makeCard(spacing: 10) { stack in
            let title = NSTextField(labelWithString: L.t("Вставка текста", "Text input"))
            title.font = DS.Font.text(11, weight: .semibold)
            title.textColor = DS.Color.textTertiary
            stack.addArrangedSubview(leftAligned(title))

            stack.addArrangedSubview(autoPasteToggle)
            autoPasteToggle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.addArrangedSubview(autoEnterToggle)
            autoEnterToggle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.addArrangedSubview(simulateTypingToggle)
            simulateTypingToggle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func makeTranscriptionProviderCard() -> NSView {
        makeCard(spacing: 12) { stack in
            let title = NSTextField(labelWithString: L.t("Транскрибация", "Transcription"))
            title.font = DS.Font.text(11, weight: .semibold)
            title.textColor = DS.Color.textTertiary
            stack.addArrangedSubview(leftAligned(title))

            stack.addArrangedSubview(transcriptionProviderSelector)
            transcriptionProviderSelector.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            // OpenAI-специфичные поля — скрыты когда выбрано Local
            let openAIContainer = NSStackView()
            openAIContainer.orientation = .vertical
            openAIContainer.spacing = 8
            openAIContainer.translatesAutoresizingMaskIntoConstraints = false

            let keyLabel = NSTextField(labelWithString: L.t("API-ключ OpenAI", "OpenAI API key"))
            keyLabel.font = DS.Font.text(11, weight: .semibold)
            keyLabel.textColor = DS.Color.textTertiary

            openAIKeyField.translatesAutoresizingMaskIntoConstraints = false
            openAIKeyField.heightAnchor.constraint(equalToConstant: 32).isActive = true
            openAIKeyField.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
            openAIKeyField.layer?.borderWidth = 1
            openAIKeyField.layer?.borderColor = DS.Color.glassStrokeSoft.cgColor

            openAIContainer.addArrangedSubview(leftAligned(keyLabel))
            openAIContainer.addArrangedSubview(openAIKeyField)
            openAIContainer.addArrangedSubview(openAIModelRow)
            openAIKeyField.widthAnchor.constraint(equalTo: openAIContainer.widthAnchor).isActive = true
            openAIModelRow.widthAnchor.constraint(equalTo: openAIContainer.widthAnchor).isActive = true

            let notice = NSTextField(wrappingLabelWithString: L.t(
                "⚠️ Аудиозаписи отправляются на серверы OpenAI. Ключ хранится локально на Mac.",
                "⚠️ Audio recordings are sent to OpenAI servers. The key is stored locally on your Mac."))
            notice.font = DS.Font.text(11)
            notice.textColor = NSColor.systemYellow.withAlphaComponent(0.8)
            openAIContainer.addArrangedSubview(notice)

            openAIFieldsContainer = openAIContainer
            stack.addArrangedSubview(openAIContainer)
            openAIContainer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func makeInterfaceCard() -> NSView {
        makeCard(spacing: 10) { stack in
            let title = NSTextField(labelWithString: L.t("Интерфейс", "Interface"))
            title.font = DS.Font.text(11, weight: .semibold)
            title.textColor = DS.Color.textTertiary
            stack.addArrangedSubview(leftAligned(title))

            stack.addArrangedSubview(interfaceLanguageRow)
            interfaceLanguageRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.addArrangedSubview(overlayModeRow)
            overlayModeRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func makeContextPrivacyCard() -> NSView {
        makeCard(spacing: 10) { stack in
            let title = NSTextField(labelWithString: L.t("Контекст и приватность", "Context & privacy"))
            title.font = DS.Font.text(11, weight: .semibold)
            title.textColor = DS.Color.textTertiary
            stack.addArrangedSubview(leftAligned(title))

            stack.addArrangedSubview(smartContextToggle)
            smartContextToggle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    /// Карточка «Поведение приложения» — системные тумблеры:
    /// автозапуск и иконка в Dock. Звуковые сигналы живут в разделе Sound.
    private func makeAppBehaviorCard() -> NSView {
        makeCard(spacing: 10) { stack in
            let title = NSTextField(labelWithString: L.t("Поведение приложения", "App behavior"))
            title.font = DS.Font.text(11, weight: .semibold)
            title.textColor = DS.Color.textTertiary
            stack.addArrangedSubview(leftAligned(title))

            stack.addArrangedSubview(launchAtLoginToggle)
            launchAtLoginToggle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.addArrangedSubview(showInDockToggle)
            showInDockToggle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.addArrangedSubview(saveRecordingsToggle)
            saveRecordingsToggle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.addArrangedSubview(recordingsRetentionRow)
            recordingsRetentionRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func makeUpdatesCard() -> NSView {
        makeCard(spacing: 10) { stack in
            let title = NSTextField(labelWithString: L.t("Обновления", "Updates"))
            title.font = DS.Font.text(11, weight: .semibold)
            title.textColor = DS.Color.textTertiary
            stack.addArrangedSubview(leftAligned(title))

            stack.addArrangedSubview(automaticUpdatesToggle)
            automaticUpdatesToggle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            let versionLabel = NSTextField(labelWithString: L.t(
                "Версия \(AppBrand.versionString)", "Version \(AppBrand.versionString)"
            ))
            versionLabel.font = DS.Font.text(12)
            versionLabel.textColor = DS.Color.textSecondary

            let updateRow = NSStackView(views: [versionLabel, NSView(), checkForUpdatesButton])
            updateRow.orientation = .horizontal
            updateRow.alignment = .centerY
            updateRow.spacing = 12
            stack.addArrangedSubview(updateRow)
            updateRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func makeDiagnosticsCard() -> NSView {
        makeCard(spacing: 10) { stack in
            let title = NSTextField(labelWithString: L.t("Логи", "Logs"))
            title.font = DS.Font.text(11, weight: .semibold)
            title.textColor = DS.Color.textTertiary
            stack.addArrangedSubview(leftAligned(title))

            stack.addArrangedSubview(diagnosticsLoggingToggle)
            diagnosticsLoggingToggle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            let row = NSStackView(views: [NSView(), showDiagnosticsLogButton])
            row.orientation = .horizontal
            row.alignment = .centerY
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func makePermissionsCard() -> NSView {
        makeCard { stack in
            let title = NSTextField(labelWithString: L.t("Разрешения", "Permissions"))
            title.font = DS.Font.text(11, weight: .semibold)
            title.textColor = DS.Color.textTertiary

            let hint = NSTextField(wrappingLabelWithString: L.t(
                "Зелёный — доступ уже выдан, повторно подтверждать не нужно. Янтарный — доступ требуется: нажмите «Выдать доступ».",
                "Green means access is already granted — no need to confirm again. Amber means access is required: tap “Grant access”."
            ))
            hint.font = DS.Font.text(12)
            hint.textColor = DS.Color.textSecondary

            stack.addArrangedSubview(leftAligned(title))
            stack.addArrangedSubview(leftAligned(hint))
            stack.addArrangedSubview(spacer(height: 6))

            let micRow = makePermissionRow(
                title: L.t("Микрофон", "Microphone"),
                detail: L.t("Запись речи", "Speech recording"),
                statusLabel: microphoneStatusLabel,
                button: microphoneButton)
            stack.addArrangedSubview(micRow)
            micRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            let axRow = makePermissionRow(
                title: L.t("Авто-вставка", "Auto-paste"),
                detail: L.t("Accessibility — вставка текста и умный контекст",
                            "Accessibility — text insertion and smart context"),
                statusLabel: accessibilityStatusLabel,
                button: accessibilityButton)
            stack.addArrangedSubview(axRow)
            axRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            renderPermissions()
        }
    }

    /// Строка одного разрешения: название/описание слева, статус-индикатор и кнопка справа.
    private func makePermissionRow(
        title: String,
        detail: String,
        statusLabel: NSTextField,
        button: StyledButton
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = DS.Font.text(14, weight: .semibold)
        titleLabel.textColor = DS.Color.textPrimary

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = DS.Font.text(12)
        detailLabel.textColor = DS.Color.textSecondary

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        statusLabel.font = DS.Font.text(12, weight: .semibold)
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [textStack, NSView(), statusLabel, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    /// Обновляет индикаторы и прячет кнопку «Выдать доступ», если разрешение уже есть.
    private func renderPermissions() {
        guard microphoneButton != nil, accessibilityButton != nil else { return }
        let micGranted = MicrophonePermission.isGranted
        let axGranted = AccessibilityPermission.isTrusted
        applyPermissionStatus(microphoneStatusLabel, granted: micGranted)
        applyPermissionStatus(accessibilityStatusLabel, granted: axGranted)
        microphoneButton.isHidden = micGranted
        accessibilityButton.isHidden = axGranted
    }

    private func applyPermissionStatus(_ label: NSTextField, granted: Bool) {
        label.stringValue = granted
            ? L.t("✓ Разрешено", "✓ Granted")
            : L.t("○ Нужен доступ", "○ Needs access")
        label.textColor = granted ? Self.permissionGreen : Self.permissionAmber
    }

    // MARK: - Render-помощники

    private func renderHome(historyEntries: [DictationEntry], usageDashboard: UsageDashboardSnapshot) {
        currentUsageDashboard = usageDashboard
        greetingTitleLabel.stringValue = L.t("С возвращением 👋", "Welcome back 👋")
        greetingDetailLabel.stringValue = L.t(
            "Зажмите горячую клавишу и говорите — текст распознается и вставится сам.",
            "Hold the hotkey and speak — your words are transcribed and pasted automatically.")
        dictationCountLabel.stringValue = "\(usageDashboard.lifetime.dictationCount)"
        wordCountLabel.stringValue = formattedNumber(usageDashboard.lifetime.wordCount)
        durationLabel.stringValue = formattedDuration(usageDashboard.lifetime.durationSeconds)
        renderUsageDashboard()
        let searching = !historySearchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        historySearchField.isHidden = historyEntries.isEmpty && !searching

        allHistoryEntries = historyEntries
        renderHistoryRows(historyEntries, searching: searching)
    }

    private func renderUsageDashboard() {
        let stats = currentUsageDashboard.stats(for: .month)
        usageActiveDaysLabel.stringValue = L.t(
            "\(stats.activeDays) из \(UsagePeriod.month.dayCount)",
            "\(stats.activeDays) of \(UsagePeriod.month.dayCount)"
        )
        usageSessionsLabel.stringValue = "\(stats.sessionCount)"
        usageStreakLabel.stringValue = L.t(
            "\(currentUsageDashboard.currentStreak) дн.",
            "\(currentUsageDashboard.currentStreak)d"
        )
        usageLongestStreakLabel.stringValue = L.t(
            "\(currentUsageDashboard.longestStreak) дн.",
            "\(currentUsageDashboard.longestStreak)d"
        )
        usageActivityChart.dailyUsage = stats.daily
        usageActivityChartHeight.constant = usageActivityChart.preferredHeight
    }

    private func renderHistoryRows(_ entries: [DictationEntry], searching: Bool = false) {
        pendingHistoryEntries = entries
        pendingHistorySearching = searching
        historyRenderToken &+= 1   // отменяем незавершённые порции прошлого рендера
        // Перестраиваем список только когда раздел истории виден — иначе откладываем
        // до открытия (избегаем дорогой синхронной раскладки сотен строк впустую).
        guard currentSection == .history else {
            historyNeedsRender = true
            return
        }
        performHistoryRender()
    }

    /// Готовит плоский список (заголовки дней + строки) и вставляет его порциями:
    /// первая порция — синхронно (мгновенное появление), остальное — по runloop'у.
    private func performHistoryRender() {
        historyNeedsRender = false
        let entries = pendingHistoryEntries
        let searching = pendingHistorySearching

        homeHistoryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !entries.isEmpty else {
            let message = searching
                ? L.t("Ничего не найдено. Очистите поиск, чтобы вернуться к истории.",
                      "Nothing found. Clear the search to return to history.")
                : L.t("История появится здесь после первой диктовки",
                      "History will appear here after your first dictation")
            let empty = DashboardEmptyHistoryView(message: message)
            homeHistoryStack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: homeHistoryStack.widthAnchor).isActive = true
            return
        }

        var items: [HistoryListItem] = []
        var lastDayKey = ""
        for entry in entries {
            let dayKey = Self.dayHeader(for: entry.createdAt)
            if dayKey != lastDayKey { lastDayKey = dayKey; items.append(.dayHeader(dayKey)) }
            items.append(.entry(entry))
        }
        appendHistoryItems(items, from: 0, token: historyRenderToken)
    }

    private func appendHistoryItems(_ items: [HistoryListItem], from index: Int, token: Int) {
        guard token == historyRenderToken else { return }   // отменено более новым рендером
        // Первая порция — синхронная и маленькая (мгновенное открытие); остальное
        // дозагружается крупнее и асинхронно, не блокируя кадр.
        let size = index == 0 ? Self.historyFirstChunkSize : Self.historyChunkSize
        let end = min(index + size, items.count)
        for i in index..<end {
            let view: NSView
            switch items[i] {
            case .dayHeader(let title):
                view = HomeHistoryDayHeaderView(title: title)
            case .entry(let entry):
                view = HomeHistoryRowView(
                    entry: entry,
                    onCopy: { [weak self] text in self?.delegate?.controlPanelDidCopyText(text) },
                    onDelete: { [weak self] in self?.delegate?.controlPanelDidDeleteEntry(id: entry.id) }
                )
            }
            homeHistoryStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: homeHistoryStack.widthAnchor).isActive = true
        }
        guard end < items.count else { return }
        // Остаток — следующей порцией, не блокируя текущий кадр.
        DispatchQueue.main.async { [weak self] in
            self?.appendHistoryItems(items, from: end, token: token)
        }
    }

    private static func dayHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L.t("СЕГОДНЯ", "TODAY") }
        if calendar.isDateInYesterday(date) { return L.t("ВЧЕРА", "YESTERDAY") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L.current == .en ? "en_US" : "ru_RU")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date).uppercased()
    }

    private func renderModelSettings(
        settings: AppSettings,
        installedModelIDs: Set<String>,
        isDownloadingModel: Bool,
        downloadStatus: String
    ) {
        let selectedID = settings.selectedModelID
        modelPopup.removeAllItems()

        for profile in ModelProfile.builtInProfiles {
            let installed = installedModelIDs.contains(profile.id)
            let suffix = installed ? L.t("установлена", "installed") : profile.sizeLabel
            modelPopup.addItem(withTitle: "\(profile.menuTitle) — \(suffix)")
            modelPopup.lastItem?.representedObject = profile.id
        }

        if let index = modelPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == selectedID }) {
            modelPopup.selectItem(at: index)
        }

        let selectedProfile = ModelProfile.profile(id: selectedID)
        let selectedInstalled = installedModelIDs.contains(selectedID)
        modelPopup.isEnabled = !isDownloadingModel
        downloadModelButton.isEnabled = !isDownloadingModel && !selectedInstalled
        downloadModelButton.title = isDownloadingModel ? L.t("Скачивание…", "Downloading…") : L.t("Скачать модель", "Download model")
        downloadProgressIndicator.isHidden = !isDownloadingModel
        downloadProgressIndicator.doubleValue = progressValue(from: downloadStatus)

        // Описание выбранной модели — без повтора оценок (они уже видны на карточке).
        modelComparisonLabel.stringValue = selectedProfile?.description ?? ""

        // Короткий статус-действие. Оценки/описание здесь не повторяем.
        if !downloadStatus.isEmpty {
            modelStatusLabel.stringValue = downloadStatus
            modelStatusLabel.textColor = DS.Color.info
        } else if selectedInstalled {
            modelStatusLabel.stringValue = L.t("✓ Готова к работе", "✓ Ready to use")
            modelStatusLabel.textColor = DS.Color.success
        } else {
            modelStatusLabel.stringValue = L.t(
                "Не скачана — нажмите «Скачать модель» (\(selectedProfile?.sizeLabel ?? ""))",
                "Not downloaded — press “Download model” (\(selectedProfile?.sizeLabel ?? ""))")
            modelStatusLabel.textColor = DS.Color.textSecondary
        }

        for profile in ModelProfile.builtInProfiles {
            modelOptionViews[profile.id]?.configure(
                profile: profile,
                isSelected: profile.id == selectedID,
                isInstalled: installedModelIDs.contains(profile.id)
            )
        }
    }

    private func renderSettings(_ settings: AppSettings) {
        currentSpokenLanguages = settings.spokenLanguages
        currentAutoDetectLanguage = settings.autoDetectLanguage
        // languageField держим синхронным с эффективным языком — его использует бандл applySettings.
        languageField.stringValue = settings.effectiveTranscriptionLanguage
        languageRow.setValue(Self.spokenLanguagesSummary(
            codes: settings.spokenLanguages, autoDetect: settings.autoDetectLanguage
        ))
        promptField.stringValue = settings.initialPrompt
        whisperBinaryPathField.stringValue = settings.whisperBinaryPath
        modelDirectoryPathField.stringValue = settings.modelDirectoryPath
        toggleHotkeyLabel.stringValue = settings.toggleHotkey.displayText
        pushToTalkHotkeyLabel.stringValue = settings.pushToTalkHotkey.displayText
        if let item = polishLevelPopup.itemArray.first(where: { ($0.representedObject as? String) == settings.polishLevel.rawValue }) {
            polishLevelPopup.select(item)
        }
        polishLevelSelector.select(id: settings.polishLevel.rawValue)
        cloudPolishPanel?.isHidden = settings.polishLevel != .cloud
        mediaInterruptionSelector.select(id: settings.mediaInterruptionMode.rawValue)
        autoPasteToggle.setOn(settings.autoPasteEnabled)
        removeFillersToggle.setOn(settings.removeFillerWords)
        smartContextToggle.setOn(settings.smartContextEnabled)
        launchAtLoginToggle.setOn(settings.launchAtLogin)
        showInDockToggle.setOn(settings.showInDock)
        playSoundsToggle.setOn(settings.playFeedbackSounds)
        saveRecordingsToggle.setOn(settings.saveRecordings)
        autoEnterToggle.setOn(settings.autoEnterAfterPaste)
        simulateTypingToggle.setOn(settings.pasteMode == .simulateTyping)
        transcriptionProviderSelector.select(id: settings.transcriptionProvider.rawValue)
        openAIFieldsContainer?.isHidden = settings.transcriptionProvider != .openAI
        localModelCard?.isHidden = settings.transcriptionProvider == .openAI
        if !settings.openAIAPIKey.isEmpty {
            openAIKeyField.stringValue = settings.openAIAPIKey
        }
        currentOpenAIModel = settings.openAITranscriptionModel
        openAIModelRow.setValue(settings.openAITranscriptionModel.displayName)
        currentInputDeviceUID = settings.inputDeviceUID
        microphoneRow.setValue(microphoneDisplayName(settings.inputDeviceUID))
        currentInterfaceLanguage = settings.interfaceLanguage
        interfaceLanguageRow.setValue(L.languageName(settings.interfaceLanguage))
        currentOverlayDisplayMode = settings.overlayDisplayMode.rawValue
        overlayModeRow.setValue(settings.overlayDisplayMode.displayName)
        dictionaryEditor.setEntries(settings.dictionaryReplacements)
        recordingsRetentionRow.isHidden = !settings.saveRecordings
        currentRecordingsRetention = settings.recordingsRetention.rawValue
        recordingsRetentionRow.setValue(settings.recordingsRetention.displayName)
        automaticUpdatesToggle.setOn(settings.automaticallyCheckForUpdates)
        diagnosticsLoggingToggle.setOn(settings.diagnosticsLoggingEnabled)
    }

    private func progressValue(from status: String) -> Double {
        guard let percentRange = status.range(of: #"(\d+)%"#, options: .regularExpression) else {
            return 0.05
        }
        let digits = status[percentRange].dropLast()
        return (Double(digits) ?? 0) / 100
    }

    // MARK: - Общие помощники

    private func leftAligned(_ view: NSView) -> NSStackView {
        let row = NSStackView(views: [view, NSView()])
        row.orientation = .horizontal
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func labeledColumn(label: String, tooltip: String? = nil, control: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let labelView = NSTextField(labelWithString: label)
        labelView.font = DS.Font.text(12, weight: .medium)
        labelView.textColor = DS.Color.textSecondary
        labelView.alignment = .left
        labelView.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Заголовок поля: либо просто подпись, либо подпись + иконка-подсказка (ⓘ).
        let header: NSView
        if let tooltip {
            let row = NSStackView(views: [labelView, makeInfoIcon(tooltip), NSView()])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 5
            header = row
        } else {
            header = labelView
        }
        header.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(header)
        container.addSubview(control)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.topAnchor.constraint(equalTo: container.topAnchor),

            control.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 7),
            control.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeInfoIcon(_ tooltip: String) -> NSView {
        InfoIconView(tooltip: tooltip)
    }

    private func makeUsageActivityCard() -> NSView {
        let card = GlassCardView(cornerRadius: DS.Radius.panel, style: .panel)
        card.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L.t("Активность", "Activity"))
        title.font = DS.Font.heading(14, weight: .semibold)
        title.textColor = DS.Color.textPrimary

        let header = NSStackView(views: [title])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        usageActivityChart.translatesAutoresizingMaskIntoConstraints = false
        usageActivityChartHeight = usageActivityChart.heightAnchor.constraint(equalToConstant: 62)
        usageActivityChartHeight.isActive = true

        let activityMetrics = NSStackView(views: [
            makeCompactMetric(title: L.t("Активные дни", "Active days"), valueLabel: usageActiveDaysLabel),
            makeCompactMetric(title: L.t("Сессии", "Sessions"), valueLabel: usageSessionsLabel),
            makeCompactMetric(title: L.t("Стрик", "Streak"), valueLabel: usageStreakLabel),
            makeCompactMetric(title: L.t("Дольше всего", "Longest streak"), valueLabel: usageLongestStreakLabel)
        ])
        activityMetrics.orientation = .horizontal
        activityMetrics.distribution = .fillEqually
        activityMetrics.spacing = 10

        let stack = NSStackView(views: [header, usageActivityChart, activityMetrics])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        for view in [header, usageActivityChart, activityMetrics] as [NSView] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return card
    }

    private func makeCompactMetric(title: String, valueLabel: NSTextField) -> NSView {
        valueLabel.font = DS.Font.mono(15, weight: .semibold)
        valueLabel.textColor = DS.Color.textPrimary
        valueLabel.alignment = .left

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = DS.Font.text(10, weight: .medium)
        titleLabel.textColor = DS.Color.textTertiary

        let stack = NSStackView(views: [valueLabel, titleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }

    private func makeMetricTile(title: String, valueLabel: NSTextField) -> NSView {
        // C-редизайн: плитка на настоящем стекле (Liquid Glass), а не плоская заливка.
        let tile = GlassCardView(cornerRadius: DS.Radius.control + 3, style: .panel)
        tile.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = DS.Font.mono(22, weight: .semibold)
        valueLabel.textColor = DS.Color.textPrimary
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = DS.Font.text(11, weight: .medium)
        titleLabel.textColor = DS.Color.textTertiary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        tile.addSubview(valueLabel)
        tile.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            tile.heightAnchor.constraint(equalToConstant: 64),
            valueLabel.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 14),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -14),
            valueLabel.topAnchor.constraint(equalTo: tile.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: valueLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 3)
        ])
        return tile
    }

    /// Тайл-шорткат на главной (как «Get started» у SuperWhisper): иконка + заголовок +
    /// подпись, по клику переключает раздел сайдбара через `onClick`.
    private func makeQuickActionTile(icon: String, title: String, subtitle: String, onClick: @escaping () -> Void) -> NSView {
        QuickActionTile(icon: icon, title: title, subtitle: subtitle, onClick: onClick)
    }

    private func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        let m = L.t("мин", "min")
        let h = L.t("ч", "h")
        if minutes < 60 { return "\(minutes) \(m)" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) \(h)" : "\(hours) \(h) \(rest) \(m)"
    }

    private func configureTextField(_ field: NSTextField) {
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.06)
        field.textColor = DS.Color.textPrimary
        field.font = DS.Font.text(13)
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingMiddle
        field.wantsLayer = true
        field.layer?.cornerRadius = DS.Radius.control
        field.layer?.cornerCurve = .continuous
        field.layer?.borderWidth = 1
        field.layer?.borderColor = DS.Color.glassStrokeSoft.cgColor
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        if let cell = field.cell as? NSTextFieldCell {
            cell.usesSingleLineMode = field !== promptField
            cell.wraps = field === promptField
            cell.lineBreakMode = field === promptField ? .byWordWrapping : .byTruncatingMiddle
            cell.drawsBackground = false
        }
    }

    // MARK: - Действия

    @objc private func startRecording() { delegate?.controlPanelDidStartRecording() }
    @objc private func stopAndTranscribe() { delegate?.controlPanelDidStopAndTranscribe() }
    @objc private func cancelRecording() { delegate?.controlPanelDidCancelRecording() }
    @objc private func transcribeTestAudio() { delegate?.controlPanelDidTranscribeTestAudio() }

    @objc private func selectModel() {
        guard let id = modelPopup.selectedItem?.representedObject as? String else { return }
        delegate?.controlPanelDidSelectModel(id: id)
    }

    @objc private func downloadSelectedModel() { delegate?.controlPanelDidDownloadSelectedModel() }
    @objc private func downloadLocalLLMModel() { delegate?.controlPanelDidDownloadLocalLLMModel() }
    @objc private func openModelsFolder() { delegate?.controlPanelDidOpenModelDirectory() }

    @objc private func beginToggleHotkeyCapture() {
        beginHotkeyCapture(for: .toggleRecording, label: toggleHotkeyLabel)
    }

    @objc private func beginPushToTalkHotkeyCapture() {
        beginHotkeyCapture(for: .pushToTalk, label: pushToTalkHotkeyLabel)
    }

    private func beginHotkeyCapture(for action: DictationHotkeyAction, label: NSTextField) {
        if let hotkeyCaptureMonitor {
            NSEvent.removeMonitor(hotkeyCaptureMonitor)
            self.hotkeyCaptureMonitor = nil
        }

        label.stringValue = L.t("Нажмите…", "Press…")
        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                guard event.modifierFlags.contains(.function) else {
                    return nil
                }
                let hotkey = Hotkey.fn
                label.stringValue = hotkey.displayText
                self.delegate?.controlPanelDidSetHotkey(hotkey, for: action)
                if let monitor = self.hotkeyCaptureMonitor {
                    NSEvent.removeMonitor(monitor)
                    self.hotkeyCaptureMonitor = nil
                }
                return nil
            }

            guard event.type == .keyDown else { return nil }
            let modifiers = event.hotkeyModifierNames
            guard !modifiers.isEmpty else {
                label.stringValue = L.t("Модификатор", "Modifier")
                return nil
            }
            guard !Hotkey.isModifierOnlyKeyCode(UInt16(event.keyCode)) else {
                return nil
            }

            let hotkey = Hotkey(keyCode: UInt16(event.keyCode), modifierFlags: modifiers)
            label.stringValue = hotkey.displayText
            self.delegate?.controlPanelDidSetHotkey(hotkey, for: action)

            if let monitor = self.hotkeyCaptureMonitor {
                NSEvent.removeMonitor(monitor)
                self.hotkeyCaptureMonitor = nil
            }
            return nil
        }
    }

    @objc private func applySettings() {
        delegate?.controlPanelDidApplySettings(
            language: languageField.stringValue,
            initialPrompt: promptField.stringValue,
            whisperBinaryPath: whisperBinaryPathField.stringValue,
            modelDirectoryPath: modelDirectoryPathField.stringValue
        )
    }

    @objc private func selectPolishLevel() {
        guard
            let rawValue = polishLevelPopup.selectedItem?.representedObject as? String,
            let level = PolishLevel(rawValue: rawValue)
        else { return }
        delegate?.controlPanelDidSetPolishLevel(level)
    }

    @objc private func presentLanguagePicker() {
        guard let window = self.window else { return }
        // Языки распознавания берём из полного списка whisper (без «auto» — за него
        // отвечает отдельный тумблер Auto-detect в модалке).
        let items = Self.spokenLanguageCatalog.map {
            LanguagesPickerSheet.Item(code: $0.code, title: $0.title, native: $0.native)
        }
        let sheet = LanguagesPickerSheet(
            items: items,
            selected: currentSpokenLanguages,
            autoDetect: currentAutoDetectLanguage
        ) { [weak self] codes, autoDetect in
            guard let self else { return }
            self.currentSpokenLanguages = codes
            self.currentAutoDetectLanguage = autoDetect
            self.languageRow.setValue(Self.spokenLanguagesSummary(codes: codes, autoDetect: autoDetect))
            // Держим languageField синхронным (эффективный язык), чтобы бандл applySettings не конфликтовал.
            self.languageField.stringValue = autoDetect ? "auto" : (codes.first ?? "auto")
            self.delegate?.controlPanelDidSetSpokenLanguages(codes, autoDetect: autoDetect)
        }
        languagesPickerSheet = sheet
        sheet.present(in: window, anchor: languageRow)
    }

    /// Краткая сводка выбранных языков для строки настроек.
    static func spokenLanguagesSummary(codes: [String], autoDetect: Bool) -> String {
        let names = codes.map { code in spokenLanguageCatalog.first { $0.code == code }?.title ?? code.uppercased() }
        if autoDetect {
            return names.isEmpty
                ? L.t("Автоопределение", "Auto-detect")
                : L.t("Авто: ", "Auto: ") + names.joined(separator: ", ")
        }
        return names.isEmpty ? L.t("Автоопределение", "Auto-detect") : names.joined(separator: ", ")
    }

    @objc private func presentMicrophonePicker() {
        guard let window = self.window else { return }
        var items = [OptionPickerSheet.Item(id: "", title: L.t("Системный по умолчанию", "System default"))]
        items += AudioInputDevices.available().map { OptionPickerSheet.Item(id: $0.uid, title: $0.name) }
        let sheet = OptionPickerSheet(
            title: L.t("Микрофон", "Microphone"),
            items: items,
            current: currentInputDeviceUID
        ) { [weak self] uid in
            guard let self else { return }
            self.currentInputDeviceUID = uid
            self.microphoneRow.setValue(self.microphoneDisplayName(uid))
            self.delegate?.controlPanelDidSetInputDevice(uid: uid)
        }
        microphonePickerSheet = sheet
        sheet.present(in: window, anchor: microphoneRow)
    }

    @objc private func presentInterfaceLanguagePicker() {
        guard let window = self.window else { return }
        let items = [OptionPickerSheet.Item(
            id: AppSettings.automaticInterfaceLanguage,
            title: L.languageName(AppSettings.automaticInterfaceLanguage)
        )] + AppSettings.supportedInterfaceLanguages.map { code in
            OptionPickerSheet.Item(id: code, title: L.languageName(code))
        }
        let sheet = OptionPickerSheet(
            title: L.t("Язык интерфейса", "Interface language"),
            items: items,
            current: currentInterfaceLanguage
        ) { [weak self] code in
            guard let self else { return }
            self.currentInterfaceLanguage = code
            self.delegate?.controlPanelDidSetInterfaceLanguage(code)
        }
        interfaceLanguagePickerSheet = sheet
        sheet.present(in: window, anchor: interfaceLanguageRow)
    }

    @objc private func presentOverlayModePicker() {
        guard let window = self.window else { return }
        let items = OverlayDisplayMode.allCases.map {
            OptionPickerSheet.Item(id: $0.rawValue, title: $0.displayName)
        }
        let sheet = OptionPickerSheet(
            title: L.t("Оверлей записи", "Recording overlay"),
            items: items,
            current: currentOverlayDisplayMode
        ) { [weak self] rawValue in
            guard let self, let mode = OverlayDisplayMode(rawValue: rawValue) else { return }
            self.currentOverlayDisplayMode = rawValue
            self.overlayModeRow.setValue(mode.displayName)
            self.delegate?.controlPanelDidSetOverlayDisplayMode(mode)
        }
        overlayModePickerSheet = sheet
        sheet.present(in: window, anchor: overlayModeRow)
    }

    @objc private func presentRecordingsRetentionPicker() {
        guard let window = self.window else { return }
        let items = RecordingsRetentionPeriod.allCases.map {
            OptionPickerSheet.Item(id: $0.rawValue, title: $0.displayName)
        }
        let sheet = OptionPickerSheet(
            title: L.t("Хранить записи", "Keep recordings for"),
            items: items,
            current: currentRecordingsRetention
        ) { [weak self] rawValue in
            guard let self, let retention = RecordingsRetentionPeriod(rawValue: rawValue) else { return }
            self.currentRecordingsRetention = rawValue
            self.recordingsRetentionRow.setValue(retention.displayName)
            self.delegate?.controlPanelDidSetRecordingsRetention(retention)
        }
        recordingsRetentionPickerSheet = sheet
        sheet.present(in: window, anchor: recordingsRetentionRow)
    }

    /// Имя выбранного микрофона для подписи в строке (или «системный по умолчанию»).
    private func microphoneDisplayName(_ uid: String) -> String {
        if uid.isEmpty { return L.t("Системный", "System default") }
        return AudioInputDevices.name(forUID: uid) ?? L.t("Системный", "System default")
    }

    /// Доступные языки распознавания (whisper-коды). Авто — определять по речи.
    static let languageOptions: [(code: String, title: String)] = [
        ("auto", "Автоопределение"),
        ("ru", "Русский"),
        ("en", "English"),
        ("uk", "Українська"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("es", "Español"),
        ("it", "Italiano"),
        ("pt", "Português"),
        ("pl", "Polski"),
        ("nl", "Nederlands"),
        ("tr", "Türkçe"),
        ("zh", "中文"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("ar", "العربية")
    ]

    static func languageDisplayName(_ code: String) -> String {
        if code == "auto" || code.isEmpty { return L.t("Автоопределение", "Auto-detect") }
        return languageOptions.first { $0.code == code }?.title ?? code
    }

    /// Полный каталог языков для модалки выбора (whisper-коды). title — англ. имя для поиска,
    /// native — самоназвание для подписи. Русский и English — первыми.
    static let spokenLanguageCatalog: [(code: String, title: String, native: String)] = [
        ("ru", "Russian", "Русский"),
        ("en", "English", "English"),
        ("uk", "Ukrainian", "Українська"),
        ("de", "German", "Deutsch"),
        ("fr", "French", "Français"),
        ("es", "Spanish", "Español"),
        ("it", "Italian", "Italiano"),
        ("pt", "Portuguese", "Português"),
        ("pl", "Polish", "Polski"),
        ("nl", "Dutch", "Nederlands"),
        ("tr", "Turkish", "Türkçe"),
        ("cs", "Czech", "Čeština"),
        ("sk", "Slovak", "Slovenčina"),
        ("be", "Belarusian", "Беларуская"),
        ("kk", "Kazakh", "Қазақша"),
        ("ka", "Georgian", "ქართული"),
        ("hy", "Armenian", "Հայերեն"),
        ("az", "Azerbaijani", "Azərbaycan"),
        ("uz", "Uzbek", "Oʻzbek"),
        ("ro", "Romanian", "Română"),
        ("sv", "Swedish", "Svenska"),
        ("no", "Norwegian", "Norsk"),
        ("da", "Danish", "Dansk"),
        ("fi", "Finnish", "Suomi"),
        ("el", "Greek", "Ελληνικά"),
        ("he", "Hebrew", "עברית"),
        ("ar", "Arabic", "العربية"),
        ("fa", "Persian", "فارسی"),
        ("hi", "Hindi", "हिन्दी"),
        ("zh", "Chinese", "中文"),
        ("ja", "Japanese", "日本語"),
        ("ko", "Korean", "한국어"),
        ("vi", "Vietnamese", "Tiếng Việt"),
        ("th", "Thai", "ไทย"),
        ("id", "Indonesian", "Indonesia"),
        ("hu", "Hungarian", "Magyar"),
        ("bg", "Bulgarian", "Български"),
        ("sr", "Serbian", "Српски"),
        ("hr", "Croatian", "Hrvatski"),
        ("ca", "Catalan", "Català")
    ]

    @objc private func historySearchChanged() {
        // Делегируем поиск AppDelegate — тот использует SQLite-индекс.
        delegate?.controlPanelDidSearchHistory(query: historySearchField.stringValue)
    }

    @objc private func copyLast() { delegate?.controlPanelDidCopyLastDictation() }
    @objc private func openHistory() { delegate?.controlPanelDidOpenHistory() }
    @objc private func clearHistory() { delegate?.controlPanelDidClearHistory() }
    @objc private func openMicrophoneSettings() { delegate?.controlPanelDidOpenMicrophoneSettings() }
    @objc private func openAccessibilitySettings() { delegate?.controlPanelDidOpenAccessibilitySettings() }
    @objc private func checkForUpdates() { delegate?.controlPanelDidRequestCheckForUpdates() }
    @objc private func showDiagnosticsLog() { delegate?.controlPanelDidRequestShowDiagnosticsLog() }

    @objc private func openAIKeyChanged() {
        delegate?.controlPanelDidSetOpenAIAPIKey(openAIKeyField.stringValue)
    }

    private func showOpenAIModelPicker() {
        guard let window = self.window else { return }
        let items = OpenAITranscriptionModel.allCases.map {
            OptionPickerSheet.Item(id: $0.rawValue, title: $0.displayName)
        }
        let picker = OptionPickerSheet(
            title: L.t("Модель OpenAI", "OpenAI model"),
            items: items,
            current: currentOpenAIModel.rawValue
        ) { [weak self] id in
            guard let self, let model = OpenAITranscriptionModel(rawValue: id) else { return }
            self.currentOpenAIModel = model
            self.openAIModelRow.setValue(model.displayName)
            self.delegate?.controlPanelDidSetOpenAIModel(model)
        }
        openAIModelPickerSheet = picker
        picker.present(in: window, anchor: openAIModelRow)
    }
}

// MARK: - Элемент бокового меню

@MainActor
private final class SidebarItem: NSView {
    private let onSelect: () -> Void
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let selectedAccentLayer = CAGradientLayer()
    private var trackingArea: NSTrackingArea?
    private var hovering = false

    var isSelected = false { didSet { updateAppearance() } }

    init(section: PanelSection, onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        selectedAccentLayer.colors = [
            NSColor.clear.cgColor,
            DS.Color.accent.withAlphaComponent(0.52).cgColor
        ]
        selectedAccentLayer.startPoint = CGPoint(x: 0, y: 0.5)
        selectedAccentLayer.endPoint = CGPoint(x: 1, y: 0.5)
        selectedAccentLayer.opacity = 0
        layer?.addSublayer(selectedAccentLayer)

        iconView.image = NSImage(systemSymbolName: section.icon, accessibilityDescription: section.title)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = section.title
        titleLabel.font = DS.Font.text(13, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        selectedAccentLayer.frame = NSRect(x: max(0, bounds.maxX - 72), y: 0, width: 72, height: bounds.height)
    }

    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.105).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            selectedAccentLayer.opacity = 1
            iconView.contentTintColor = DS.Color.textPrimary
            titleLabel.textColor = .white
        } else if hovering {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.075).cgColor
            layer?.borderWidth = 0
            selectedAccentLayer.opacity = 0
            iconView.contentTintColor = DS.Color.textPrimary
            titleLabel.textColor = DS.Color.textPrimary
        } else {
            layer?.backgroundColor = .clear
            layer?.borderWidth = 0
            selectedAccentLayer.opacity = 0
            iconView.contentTintColor = DS.Color.textSecondary
            titleLabel.textColor = DS.Color.textSecondary
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateAppearance() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateAppearance() }
    override func mouseDown(with event: NSEvent) { onSelect() }

    // Весь пункт меню кликабелен (текст-метка не перехватывает клик).
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
}

private struct SelectionOption {
    let id: String
    let title: String
    let subtitle: String
}

@MainActor
private final class OptionSelectorView: NSView {
    private let stack = NSStackView()
    private var tiles: [String: OptionTileView] = [:]
    private var selectedID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .width
        stack.distribution = .fillEqually
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(options: [SelectionOption], onSelect: @escaping (String) -> Void) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        tiles.removeAll()

        for option in options {
            let tile = OptionTileView(option: option) { [weak self] id in
                self?.select(id: id)
                onSelect(id)
            }
            tiles[option.id] = tile
            stack.addArrangedSubview(tile)
            tile.heightAnchor.constraint(equalToConstant: 54).isActive = true
        }
        if let first = options.first?.id {
            select(id: selectedID ?? first)
        }
    }

    func select(id: String) {
        selectedID = id
        for (key, tile) in tiles {
            tile.isSelected = key == id
        }
    }
}

@MainActor
private final class OptionTileView: NSView {
    private let option: SelectionOption
    private let onSelect: (String) -> Void
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var hovering = false

    var isSelected = false { didSet { updateAppearance() } }

    init(option: SelectionOption, onSelect: @escaping (String) -> Void) {
        self.option = option
        self.onSelect = onSelect
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = DS.Radius.control
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        titleLabel.stringValue = option.title
        titleLabel.font = DS.Font.text(13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.stringValue = option.subtitle
        subtitleLabel.font = DS.Font.text(11)
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateAppearance() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateAppearance() }
    override func mouseDown(with event: NSEvent) { onSelect(option.id) }

    // Весь тайл кликабелен: подписи-NSTextField не должны перехватывать клик
    // (иначе по тексту описания не переключается и появляется I-beam).
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    private func updateAppearance() {
        layer?.backgroundColor = (isSelected ? DS.Color.accent.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(hovering ? 0.14 : 0.045)).cgColor
        layer?.borderColor = (isSelected ? DS.Color.accent.withAlphaComponent(0.62) : DS.Color.glassStrokeSoft).cgColor
        titleLabel.textColor = isSelected ? .white : DS.Color.textPrimary
        subtitleLabel.textColor = isSelected ? DS.Color.info : DS.Color.textTertiary
    }
}

@MainActor
private final class ModelOptionView: NSView {
    private let onSelect: (String) -> Void
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let speedBar = ScoreBarView(title: L.t("Скорость", "Speed"))
    private let accuracyBar = ScoreBarView(title: L.t("Точность", "Accuracy"))
    private var profile: ModelProfile
    private var isSelected = false
    private var isInstalled = false
    private var trackingArea: NSTrackingArea?
    private var hovering = false

    init(profile: ModelProfile, onSelect: @escaping (String) -> Void) {
        self.profile = profile
        self.onSelect = onSelect
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = DS.Radius.control
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        for label in [titleLabel, statusLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }

        // Метрики идут колонкой под названием: «Скорость» над «Точностью».
        // Так у всех карточек бары выровнены и сравниваются взглядом сверху вниз.
        let metrics = NSStackView(views: [speedBar, accuracyBar])
        metrics.orientation = .vertical
        metrics.alignment = .width
        metrics.spacing = 4
        metrics.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metrics)

        titleLabel.font = DS.Font.display(14, weight: .semibold)
        statusLabel.font = DS.Font.text(11, weight: .semibold)
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -12),

            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            statusLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            metrics.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metrics.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            metrics.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            metrics.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
        configure(profile: profile, isSelected: false, isInstalled: false)
    }

    required init?(coder: NSCoder) { nil }

    func configure(profile: ModelProfile, isSelected: Bool, isInstalled: Bool) {
        self.profile = profile
        self.isSelected = isSelected
        self.isInstalled = isInstalled
        titleLabel.stringValue = profile.displayName
        statusLabel.stringValue = isInstalled ? L.t("✓ Установлена", "✓ Installed") : profile.sizeLabel
        speedBar.setScore(profile.speedScore)
        accuracyBar.setScore(profile.accuracyScore)
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateAppearance() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateAppearance() }
    override func mouseDown(with event: NSEvent) { onSelect(profile.id) }

    // Клик по любому месту карточки (включая описание) выбирает модель.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    private func updateAppearance() {
        layer?.backgroundColor = (isSelected ? DS.Color.accent.withAlphaComponent(0.16) : NSColor.white.withAlphaComponent(hovering ? 0.14 : 0.045)).cgColor
        layer?.borderColor = (isSelected ? DS.Color.accent.withAlphaComponent(0.62) : DS.Color.glassStrokeSoft).cgColor
        titleLabel.textColor = .white
        statusLabel.textColor = isInstalled ? DS.Color.success : DS.Color.textTertiary
    }
}

@MainActor
private final class ScoreBarView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let track = NSView()
    private let fill = NSView()
    private var fillWidth: NSLayoutConstraint?
    private var currentScore = 0

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = DS.Font.text(10, weight: .semibold)
        titleLabel.textColor = DS.Color.textTertiary
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        valueLabel.font = DS.Font.mono(10, weight: .semibold)
        valueLabel.textColor = DS.Color.info
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        track.layer?.cornerRadius = 2.5
        track.translatesAutoresizingMaskIntoConstraints = false

        fill.wantsLayer = true
        fill.layer?.backgroundColor = DS.Color.accent.withAlphaComponent(0.85).cgColor
        fill.layer?.cornerRadius = 2.5
        fill.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(track)
        addSubview(valueLabel)
        track.addSubview(fill)

        let fillWidth = fill.widthAnchor.constraint(equalToConstant: 0)
        self.fillWidth = fillWidth

        // Компактный горизонтальный бар: «Подпись ▮▮▮▮░░ 8/10» в одну строку.
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Фиксированная ширина подписи — чтобы бары разных метрик
            // начинались на одной вертикали и сравнивались колонкой.
            titleLabel.widthAnchor.constraint(equalToConstant: 58),

            track.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            track.centerYAnchor.constraint(equalTo: centerYAnchor),
            track.heightAnchor.constraint(equalToConstant: 5),

            valueLabel.leadingAnchor.constraint(equalTo: track.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 34),

            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fillWidth
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setScore(_ score: Int) {
        let clamped = max(0, min(10, score))
        currentScore = clamped
        valueLabel.stringValue = "\(clamped)/10"
        needsLayout = true
    }

    override func layout() {
        super.layout()
        fillWidth?.constant = track.bounds.width * CGFloat(Double(currentScore) / 10)
    }
}

@MainActor
private final class DashboardHistoryRowView: NSView {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()

    init(entry: DictationEntry) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = DS.Color.glassStrokeSoft.cgColor

        let meta = NSTextField(labelWithString: "\(Self.formatter.string(from: entry.createdAt)) · \(entry.modelID)")
        meta.font = DS.Font.mono(10, weight: .medium)
        meta.textColor = DS.Color.textTertiary
        meta.translatesAutoresizingMaskIntoConstraints = false

        let text = NSTextField(wrappingLabelWithString: entry.text)
        text.font = DS.Font.text(12)
        text.textColor = DS.Color.textPrimary
        text.maximumNumberOfLines = 2
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false

        addSubview(meta)
        addSubview(text)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 66),
            meta.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            meta.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            meta.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            text.leadingAnchor.constraint(equalTo: meta.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: meta.trailingAnchor),
            text.topAnchor.constraint(equalTo: meta.bottomAnchor, constant: 5),
            text.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

/// Заголовок-разделитель дня в истории на главной («СЕГОДНЯ» / «ВЧЕРА» / дата).
@MainActor
private final class HomeHistoryDayHeaderView: NSView {
    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: title)
        label.attributedStringValue = NSAttributedString(string: title, attributes: [
            .font: DS.Font.text(10, weight: .semibold),
            .foregroundColor: DS.Color.textTertiary,
            .kern: 1.0
        ])
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
    }
    required init?(coder: NSCoder) { nil }
}

/// Строка истории на главной в стиле Flow: слева время, справа полный
/// многострочный текст (без обрезки). Действия (копировать / повторить вставку /
/// удалить) скрыты и всплывают только при наведении на строку, как и мягкая
/// подсветка. Разделители между строками рисует `HistoryDividerView`.
@MainActor
private final class HomeHistoryRowView: NSView {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()

    private let actionsContainer = NSView()
    private let entry: DictationEntry
    private let onCopyText: (String) -> Void
    private let textLabel: NSTextField
    private let rawBadge = NSTextField(labelWithString: L.t("СЫРОЙ", "RAW"))
    private var aiToggle: HistoryIconButton?
    private var showingRaw = false

    /// Есть ли сырой вариант, отличный от финального, — тогда показываем «Undo AI Edit».
    private var hasRawAlternative: Bool {
        guard let raw = entry.rawText, !raw.isEmpty else { return false }
        return raw != entry.text
    }

    /// Текст, который сейчас показан в строке (его же копирует «Копировать»).
    private var displayedText: String {
        showingRaw ? (entry.rawText ?? entry.text) : entry.text
    }

    init(
        entry: DictationEntry,
        onCopy: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.entry = entry
        self.onCopyText = onCopy
        self.textLabel = NSTextField(wrappingLabelWithString: entry.text)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        // Каждая запись — отдельная карточка с лёгкой подложкой и тонкой кромкой,
        // чтобы записи визуально отличались друг от друга (без разделителей).
        layer?.backgroundColor = Self.cardFill.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Self.cardStroke.cgColor

        let time = NSTextField(labelWithString: Self.formatter.string(from: entry.createdAt))
        time.font = DS.Font.mono(11, weight: .medium)
        time.textColor = DS.Color.textTertiary
        time.translatesAutoresizingMaskIntoConstraints = false
        time.setContentHuggingPriority(.required, for: .horizontal)

        // Бейдж «СЫРОЙ» в левом столбце под временем — виден только когда показан
        // сырой текст. Несёт состояние, даже когда панель действий скрыта.
        rawBadge.font = DS.Font.mono(9, weight: .semibold)
        rawBadge.textColor = DS.Color.accent
        rawBadge.translatesAutoresizingMaskIntoConstraints = false
        rawBadge.isHidden = true

        // Полный текст — без обрезки и без лимита строк.
        textLabel.font = DS.Font.text(12.5)
        textLabel.textColor = DS.Color.textPrimary
        textLabel.maximumNumberOfLines = 0
        textLabel.lineBreakMode = .byWordWrapping
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Действия — без собственной подложки (чистые иконки, как в референсе):
        // фон появляется только у конкретной наведённой иконки. Текст ограничен
        // своим столбцом и не заходит под иконки.
        actionsContainer.translatesAutoresizingMaskIntoConstraints = false
        actionsContainer.isHidden = true

        // Копировать — копирует то, что сейчас видно (сырой или финальный текст).
        let copyButton = HistoryIconButton(
            symbol: "doc.on.doc", tip: L.t("Копировать", "Copy"), flashOnSuccess: true
        ) { [weak self] in
            guard let self else { return }
            self.onCopyText(self.displayedText)
        }
        var buttons: [NSView] = [copyButton]
        // «Undo AI Edit» — только если AI реально менял текст (есть сырой вариант).
        if hasRawAlternative {
            let toggle = HistoryIconButton(
                symbol: "wand.and.stars", tip: Self.tipShowRaw
            ) { [weak self] in self?.toggleRaw() }
            aiToggle = toggle
            buttons.append(toggle)
        }
        buttons.append(HistoryIconButton(
            symbol: "trash", tip: L.t("Удалить", "Delete"), danger: true, action: onDelete
        ))

        let actions = NSStackView(views: buttons)
        actions.orientation = .horizontal
        actions.spacing = 2
        actions.translatesAutoresizingMaskIntoConstraints = false
        actionsContainer.addSubview(actions)
        NSLayoutConstraint.activate([
            actions.leadingAnchor.constraint(equalTo: actionsContainer.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: actionsContainer.trailingAnchor),
            actions.topAnchor.constraint(equalTo: actionsContainer.topAnchor),
            actions.bottomAnchor.constraint(equalTo: actionsContainer.bottomAnchor)
        ])

        addSubview(time)
        addSubview(rawBadge)
        addSubview(textLabel)
        addSubview(actionsContainer)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
            time.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            time.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            rawBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            rawBadge.topAnchor.constraint(equalTo: time.bottomAnchor, constant: 4),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 68),
            // Текст не доходит до правого края — там зарезервирован столбец иконок.
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -106),
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
            actionsContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            actionsContainer.topAnchor.constraint(equalTo: topAnchor, constant: 9)
        ])
    }

    required init?(coder: NSCoder) { nil }

    private static let tipShowRaw = L.t("Показать сырой текст (до AI-правки)", "Show raw text (before AI edit)")
    private static let tipShowEdited = L.t("Вернуть текст с AI-правкой", "Back to AI-edited text")

    /// Переключение между сырым и отредактированным текстом прямо в строке (Undo AI Edit).
    private func toggleRaw() {
        showingRaw.toggle()
        textLabel.stringValue = displayedText
        rawBadge.isHidden = !showingRaw
        aiToggle?.setActive(showingRaw)
        aiToggle?.setTip(showingRaw ? Self.tipShowEdited : Self.tipShowRaw)
    }

    private static let cardFill = NSColor.white.withAlphaComponent(0.035)
    private static let cardFillHover = NSColor.white.withAlphaComponent(0.08)
    private static let cardStroke = NSColor.white.withAlphaComponent(0.07)
    private static let cardStrokeHover = NSColor.white.withAlphaComponent(0.14)

    /// Вызывается контейнером (`HistoryListStackView`): ровно одна строка под
    /// курсором получает подсветку и панель действий, остальные — гасятся.
    func setHovered(_ hovering: Bool) {
        guard actionsContainer.isHidden == hovering else { return }  // нет изменения — выходим
        layer?.backgroundColor = (hovering ? Self.cardFillHover : Self.cardFill).cgColor
        layer?.borderColor = (hovering ? Self.cardStrokeHover : Self.cardStroke).cgColor
        actionsContainer.isHidden = !hovering
    }
}

/// Контейнер списка истории: ведёт hover централизованно. Одна tracking-area на
/// весь видимый список + переоценка при скролле гарантируют, что подсветка и
/// действия есть строго у одной строки под курсором (как в Flow). Решает баг
/// «залипания» действий на нескольких строках, когда per-row `mouseExited`
/// терялся при прокрутке контента под неподвижным курсором.
@MainActor
private final class HistoryListStackView: NSStackView {
    private var trackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: clip)
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: clip)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { clearHover() }

    @objc private func scrolled() {
        // При прокрутке позиция всплывающей подсказки устаревает — гасим её.
        HoverTooltip.shared.hide()
        guard let window else { return }
        let screen = NSEvent.mouseLocation
        let inWindow = window.convertPoint(fromScreen: screen)
        let inView = convert(inWindow, from: nil)
        if visibleRect.contains(inView) { hover(at: inView) } else { clearHover() }
    }

    private func hover(at point: NSPoint) {
        for case let row as HomeHistoryRowView in arrangedSubviews {
            row.setHovered(row.frame.contains(point))
        }
    }

    private func clearHover() {
        HoverTooltip.shared.hide()
        for case let row as HomeHistoryRowView in arrangedSubviews {
            row.setHovered(false)
        }
    }
}

/// Скруглённая иконка-действие в истории: hover-подсветка, опционально «опасная»
/// (красная — для удаления). Курсор — «рука», мгновенная всплывающая подсказка сверху.
@MainActor
private final class HistoryIconButton: NSView {
    private let imageView = NSImageView()
    private let action: () -> Void
    private let danger: Bool
    private var tip: String
    private let symbol: String
    private var active = false
    private let flashOnSuccess: Bool
    private var trackingArea: NSTrackingArea?
    private var hovering = false
    private var isFlashing = false

    init(symbol: String, tip: String, danger: Bool = false, flashOnSuccess: Bool = false, action: @escaping () -> Void) {
        self.action = action
        self.danger = danger
        self.tip = tip
        self.symbol = symbol
        self.flashOnSuccess = flashOnSuccess
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        setAccessibilityLabel(tip)

        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    private func updateAppearance() {
        // Во время вспышки-«галочки» цвета держит flashSuccess(); hover их не трогает.
        guard !isFlashing else { return }
        if hovering || active {
            // active (показан сырой текст) — акцентная подсветка, чтобы было видно «включено».
            let bg = danger ? DS.Color.danger.withAlphaComponent(0.16)
                : active ? DS.Color.accent.withAlphaComponent(0.18)
                : NSColor.white.withAlphaComponent(0.12)
            layer?.backgroundColor = bg.cgColor
            imageView.contentTintColor = danger ? DS.Color.danger
                : active ? DS.Color.accent
                : DS.Color.textPrimary
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            imageView.contentTintColor = danger
                ? DS.Color.danger.withAlphaComponent(0.85)
                : DS.Color.textSecondary
        }
    }

    /// Активное (нажатое) состояние toggle — подсветка держится без hover.
    func setActive(_ on: Bool) {
        active = on
        updateAppearance()
    }

    /// Динамическая смена подсказки («Показать сырой» ⇄ «Вернуть AI-правку»).
    func setTip(_ newTip: String) {
        tip = newTip
        setAccessibilityLabel(newTip)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // `.cursorUpdate` гарантирует курсор-«руку» поверх иконки, перекрывая
        // I-beam от выделяемого текста записи.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateAppearance()
        NSCursor.pointingHand.set()
        HoverTooltip.shared.show(tip, over: self)   // мгновенная подсказка сверху
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        updateAppearance()
        HoverTooltip.shared.hide()
    }

    override func mouseDown(with event: NSEvent) {
        HoverTooltip.shared.hide()
        action()
        if flashOnSuccess { flashSuccess() }
    }

    private func flashSuccess() {
        guard !isFlashing else { return }
        isFlashing = true
        imageView.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        imageView.contentTintColor = DS.Color.success
        layer?.backgroundColor = DS.Color.success.withAlphaComponent(0.12).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.isFlashing = false
            self.imageView.image = NSImage(systemSymbolName: self.symbol, accessibilityDescription: self.tip)
            self.imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            self.updateAppearance()
        }
    }
}

/// Иконка-подсказка «?» с кастомным hover-тултипом вместо нативного system toolTip.
@MainActor
private final class InfoIconView: NSView {
    private let imageView = NSImageView()
    private let tooltip: String
    private var trackingArea: NSTrackingArea?

    init(tooltip: String) {
        self.tooltip = tooltip
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        imageView.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: tooltip)
        imageView.contentTintColor = DS.Color.textTertiary
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 14),
            heightAnchor.constraint(equalToConstant: 14),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        HoverTooltip.shared.show(tooltip, over: self)
    }

    override func mouseExited(with event: NSEvent) {
        HoverTooltip.shared.hide()
    }
}

/// Мгновенная всплывающая подсказка над элементом (без системной задержки
/// `toolTip`). Один общий «пузырёк» крепится к contentView окна, чтобы не
/// обрезался скролл-вью. Появляется сразу при наведении (как в Flow).
@MainActor
private final class HoverTooltip {
    static let shared = HoverTooltip()
    private var bubble: NSView?

    func show(_ text: String, over anchor: NSView) {
        guard let content = anchor.window?.contentView else { return }
        hide()

        // Blur-подложка внутри окна.
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 8
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true

        let bubble = NSView()
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 8
        bubble.layer?.cornerCurve = .continuous
        bubble.layer?.masksToBounds = false
        bubble.layer?.backgroundColor = NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 0.92).cgColor
        bubble.layer?.borderWidth = 1
        bubble.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        bubble.layer?.shadowColor = NSColor.black.cgColor
        bubble.layer?.shadowOpacity = 0.18
        bubble.layer?.shadowRadius = 6
        bubble.layer?.shadowOffset = CGSize(width: 0, height: -2)

        blur.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(blur)

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = DS.Font.text(12, weight: .regular)
        label.textColor = NSColor.white.withAlphaComponent(0.90)
        label.maximumNumberOfLines = 6
        label.preferredMaxLayoutWidth = 260
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            blur.topAnchor.constraint(equalTo: bubble.topAnchor),
            blur.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8)
        ])

        content.addSubview(bubble)
        bubble.layoutSubtreeIfNeeded()
        let size = bubble.fittingSize

        let inWindow = anchor.convert(anchor.bounds, to: nil)
        let inContent = content.convert(inWindow, from: nil)
        var x = inContent.midX - size.width / 2
        x = max(8, min(x, content.bounds.width - size.width - 8))
        let gap: CGFloat = 7
        let y = content.isFlipped ? (inContent.minY - size.height - gap) : (inContent.maxY + gap)
        bubble.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        self.bubble = bubble
    }

    func hide() {
        bubble?.removeFromSuperview()
        bubble = nil
    }
}

@MainActor
private final class DashboardEmptyHistoryView: NSView {
    init(message: String = L.t("История появится здесь после первой диктовки",
                               "History will appear here after your first dictation")) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = DS.Color.surfaceSunken.cgColor
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = DS.Color.surfaceBorder.cgColor

        let label = NSTextField(labelWithString: message)
        label.font = DS.Font.text(12)
        label.textColor = DS.Color.textTertiary
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class InsetTextField: NSTextField {
    init(string: String) {
        super.init(frame: .zero)
        self.stringValue = string
        self.cell = InsetTextFieldCell(textCell: string)
    }

    required init?(coder: NSCoder) { nil }
}

private final class InsetTextFieldCell: NSTextFieldCell {
    private let inset = NSSize(width: 12, height: 8)

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        drawingRect.origin.x += inset.width
        drawingRect.size.width -= inset.width * 2
        if usesSingleLineMode {
            let textHeight = cellSize(forBounds: rect).height
            drawingRect.origin.y += max(0, (rect.height - textHeight) / 2)
            drawingRect.size.height = min(textHeight, rect.height)
        } else {
            drawingRect.origin.y += inset.height
            drawingRect.size.height -= inset.height * 2
        }
        return drawingRect
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

private extension NSEvent {
    var hotkeyModifierNames: [String] {
        var names: [String] = []
        if modifierFlags.contains(.control) { names.append("control") }
        if modifierFlags.contains(.option) { names.append("option") }
        if modifierFlags.contains(.shift) { names.append("shift") }
        if modifierFlags.contains(.command) { names.append("command") }
        if modifierFlags.contains(.function) { names.append("function") }
        return names
    }
}

// MARK: - Строка-свитчер настройки

/// Строка настройки со свитчером (вкл/выкл): заголовок + подпись слева, `NSSwitch` справа.
@MainActor
private final class SettingsToggleRow: NSView {
    private let onToggle: (Bool) -> Void
    private let toggle = NSSwitch()

    init(title: String, subtitle: String, onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        layer?.cornerRadius = DS.Radius.control
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = DS.Color.glassStrokeSoft.cgColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = DS.Font.text(13, weight: .medium)
        titleLabel.textColor = DS.Color.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = DS.Font.text(11)
        subtitleLabel.textColor = DS.Color.textTertiary
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        toggle.target = self
        toggle.action = #selector(switched)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(toggle)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -9),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setOn(_ on: Bool) { toggle.state = on ? .on : .off }
    @objc private func switched() { onToggle(toggle.state == .on) }
}

// MARK: - Строка-модалка настройки

/// Строка настройки, открывающая модалку выбора: заголовок + подпись слева,
/// текущее значение + шеврон справа. По клику вызывает `onClick`.
@MainActor
private final class SettingsDisclosureRow: NSView {
    private let onClick: () -> Void
    private let valueLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var hovering = false

    init(title: String, subtitle: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = DS.Radius.control
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = DS.Color.glassStrokeSoft.cgColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = DS.Font.text(13, weight: .medium)
        titleLabel.textColor = DS.Color.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = DS.Font.text(11)
        subtitleLabel.textColor = DS.Color.textTertiary
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = DS.Font.text(13, weight: .medium)
        valueLabel.textColor = DS.Color.info
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevron.contentTintColor = DS.Color.textTertiary
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(valueLabel)
        addSubview(chevron)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -12),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -12),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -9),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateBackground()
    }

    required init?(coder: NSCoder) { nil }

    func setValue(_ value: String) { valueLabel.stringValue = value }

    private func updateBackground() {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(hovering ? 0.14 : 0.04).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateBackground() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateBackground() }
    override func mouseDown(with event: NSEvent) { onClick() }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Тайл быстрого действия (Home)

/// Кликабельный тайл-шорткат на главной (как «Get started» у SuperWhisper):
/// иконка + заголовок + подпись, по клику вызывает `onClick`.
@MainActor
private final class QuickActionTile: NSView {
    private let onClick: () -> Void
    private var trackingArea: NSTrackingArea?
    private var hovering = false

    init(icon: String, title: String, subtitle: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = DS.Radius.control
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = DS.Color.glassStrokeSoft.cgColor

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        iconView.contentTintColor = DS.Color.accent
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = DS.Font.text(13, weight: .medium)
        titleLabel.textColor = DS.Color.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = DS.Font.text(11)
        subtitleLabel.textColor = DS.Color.textTertiary
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12)
        ])
        updateBackground()
    }

    required init?(coder: NSCoder) { nil }

    private func updateBackground() {
        layer?.backgroundColor = (hovering ? DS.Color.accent.withAlphaComponent(0.12) : NSColor.white.withAlphaComponent(0.05)).cgColor
        layer?.borderColor = (hovering ? DS.Color.accent.withAlphaComponent(0.5) : DS.Color.glassStrokeSoft).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateBackground() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateBackground() }
    override func mouseDown(with event: NSEvent) { onClick() }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // Весь тайл — одна кликабельная зона: дочерние лейблы не должны перехватывать
    // mouseDown/наводку (иначе курсор переключается в текстовый и клик не срабатывает).
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}

// MARK: - Модальный лист выбора одного значения

/// Модалка-лист выбора одного значения (язык и т.п.). Показывается как sheet окна.
@MainActor
private final class OptionPickerSheet: NSWindowController {
    struct Item { let id: String; let title: String }

    private let items: [Item]
    private let current: String
    private let onPick: (String) -> Void
    private weak var parentWindow: NSWindow?
    private var backdrop: PickerBackdropView?
    private var escMonitor: Any?
    private let panelSize: NSSize

    /// Компактный Liquid Glass попап: узкая колонка, без громоздких отступов.
    private static let width: CGFloat = 260
    private static let rowHeight: CGFloat = 34
    private static let maxVisibleRows = 7

    init(title: String, items: [Item], current: String, onPick: @escaping (String) -> Void) {
        self.items = items
        self.current = current
        self.onPick = onPick
        let visibleRows = min(items.count, Self.maxVisibleRows)
        let listHeight = CGFloat(visibleRows) * Self.rowHeight + CGFloat(max(0, visibleRows - 1)) * 2
        let height = 42 + listHeight + 10
        self.panelSize = NSSize(width: Self.width, height: height)
        // Borderless-панель поверх затемняющей подложки (popover-стиль), а не
        // window-modal sheet — чтобы закрывалась кликом мимо и по Esc.
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        super.init(window: panel)
        buildUI(title: title)
    }

    required init?(coder: NSCoder) { nil }

    /// Показывает попап рядом с `anchor` (контекстно, как меню), а не по центру окна.
    func present(in parent: NSWindow, anchor: NSView) {
        guard let window, let parentContent = parent.contentView else { return }
        parentWindow = parent

        // Затемняющая подложка во всё окно: ловит клики «мимо» → закрытие.
        let backdrop = PickerBackdropView(frame: parentContent.bounds)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.onClick = { [weak self] in self?.dismiss() }
        parentContent.addSubview(backdrop)
        self.backdrop = backdrop

        window.setFrameOrigin(PickerPositioning.origin(for: panelSize, anchor: anchor, in: parent))
        parent.addChildWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss(); return nil }   // Esc
            return event
        }
    }

    private func dismiss() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        backdrop?.removeFromSuperview()
        backdrop = nil
        if let window {
            parentWindow?.removeChildWindow(window)
            window.orderOut(nil)
        }
        parentWindow = nil
    }

    private func buildUI(title: String) {
        guard let window else { return }
        // Liquid Glass попап: размытие фона + тонкая кромка, без сплошной плашки.
        // Контейнер становится contentView окна напрямую (frame-based) — оборачивание
        // в дополнительный auto-layout root приводило к нулевому размеру и пустой панели.
        let glass = DS.makeGlassContainer(cornerRadius: 14, style: .popover)
        glass.frame = NSRect(origin: .zero, size: panelSize)
        glass.autoresizingMask = [.width, .height]
        window.contentView = glass

        let content = glass.contentView
        content.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: title)
        header.font = DS.Font.text(11, weight: .semibold)
        header.textColor = DS.Color.textTertiary
        header.translatesAutoresizingMaskIntoConstraints = false

        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.spacing = 2
        listStack.translatesAutoresizingMaskIntoConstraints = false
        for item in items {
            let row = PickerRow(title: item.title, selected: item.id == current) { [weak self] in
                self?.onPick(item.id)
                self?.dismiss()
            }
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }

        let clip = FlippedView()
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(listStack)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = clip

        content.addSubview(header)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            // Кнопка «Готово» убрана: выбор строки применяется и закрывает сразу
            // (плюс Esc и клик по подложке). Список тянется до низа контейнера.
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6),

            clip.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            clip.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            clip.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            clip.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            listStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: clip.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: clip.bottomAnchor)
        ])
    }
}

/// Вычисление позиции попап-пикера рядом со строкой, на которую нажали (контекстно),
/// с учётом границ экрана.
@MainActor
private enum PickerPositioning {
    static func origin(for size: NSSize, anchor: NSView, in parent: NSWindow) -> NSPoint {
        let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
        let anchorOnScreen = parent.convertToScreen(anchorInWindow)
        let screenFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchorOnScreen
        let margin: CGFloat = 8

        var x = anchorOnScreen.minX
        if x + size.width > screenFrame.maxX { x = screenFrame.maxX - size.width - margin }
        if x < screenFrame.minX { x = screenFrame.minX + margin }

        // По умолчанию — под строкой; если не влезает, показываем над ней.
        var y = anchorOnScreen.minY - size.height - 6
        if y < screenFrame.minY {
            y = anchorOnScreen.maxY + 6
        }
        if y + size.height > screenFrame.maxY { y = screenFrame.maxY - size.height - margin }

        return NSPoint(x: x, y: y)
    }
}

/// Затемняющая подложка под модалкой: клик по ней закрывает пикер (клик «мимо»).
@MainActor
private final class PickerBackdropView: NSView {
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.40).cgColor
    }

    required init?(coder: NSCoder) { nil }

    // Ловим все клики в своей области (не пропускаем к контролам под подложкой).
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Строка выбора в модалке: название + галочка у выбранного.
@MainActor
private final class PickerRow: NSView {
    private let onSelect: () -> Void
    private let selected: Bool
    private var trackingArea: NSTrackingArea?
    private var hovering = false

    init(title: String, selected: Bool, onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
        self.selected = selected
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous

        let label = NSTextField(labelWithString: title)
        label.font = DS.Font.text(12.5, weight: selected ? .semibold : .regular)
        label.textColor = selected ? .white : DS.Color.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false

        let check = NSImageView()
        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        check.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        check.contentTintColor = DS.Color.accent
        check.isHidden = !selected
        check.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(check)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            check.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateBackground()
    }

    required init?(coder: NSCoder) { nil }

    private func updateBackground() {
        let color = selected
            ? DS.Color.accent.withAlphaComponent(0.16)
            : NSColor.white.withAlphaComponent(hovering ? 0.14 : 0.0)
        layer?.backgroundColor = color.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateBackground() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateBackground() }
    override func mouseDown(with event: NSEvent) { onSelect() }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// Модалка выбора языков распознавания (мультивыбор + поиск + тумблер автоопределения),
/// в стиле Flow. Порядок выбора = приоритет: первый выбранный — основной (используется,
/// когда автоопределение выключено).
@MainActor
private final class LanguagesPickerSheet: NSWindowController, NSTextFieldDelegate {
    struct Item { let code: String; let title: String; let native: String }

    private let items: [Item]
    private var selectedCodes: [String]
    private var autoDetect: Bool
    private let onSave: ([String], Bool) -> Void

    private weak var parentWindow: NSWindow?
    private var backdrop: PickerBackdropView?
    private var escMonitor: Any?

    private let listStack = NSStackView()
    private let searchField = NSTextField()
    private let autoSwitch = NSSwitch()
    private let primaryHint = NSTextField(labelWithString: "")
    private let panelSize = NSSize(width: 340, height: 440)

    init(items: [Item], selected: [String], autoDetect: Bool, onSave: @escaping ([String], Bool) -> Void) {
        self.items = items
        self.selectedCodes = selected
        self.autoDetect = autoDetect
        self.onSave = onSave
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        super.init(window: panel)
        buildUI()
        rebuildList(filter: "")
        updatePrimaryHint()
    }

    required init?(coder: NSCoder) { nil }

    /// Показывает попап рядом с `anchor` (контекстно, как меню), а не по центру окна.
    func present(in parent: NSWindow, anchor: NSView) {
        guard let window, let parentContent = parent.contentView else { return }
        parentWindow = parent

        let backdrop = PickerBackdropView(frame: parentContent.bounds)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.onClick = { [weak self] in self?.saveAndDismiss() }
        parentContent.addSubview(backdrop)
        self.backdrop = backdrop

        window.setFrameOrigin(PickerPositioning.origin(for: panelSize, anchor: anchor, in: parent))
        parent.addChildWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.saveAndDismiss(); return nil }   // Esc
            return event
        }
    }

    private func saveAndDismiss() {
        onSave(selectedCodes, autoDetect)
        dismiss()
    }

    private func dismiss() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor); self.escMonitor = nil }
        backdrop?.removeFromSuperview()
        backdrop = nil
        if let window {
            parentWindow?.removeChildWindow(window)
            window.orderOut(nil)
        }
        parentWindow = nil
    }

    private func buildUI() {
        guard let window else { return }
        // Liquid Glass попап (как у OptionPickerSheet): размытие фона + тонкая кромка.
        // Контейнер становится contentView окна напрямую (frame-based) — оборачивание
        // в дополнительный auto-layout root приводило к нулевому размеру и пустой панели.
        let glass = DS.makeGlassContainer(cornerRadius: 14, style: .popover)
        glass.frame = NSRect(origin: .zero, size: panelSize)
        glass.autoresizingMask = [.width, .height]
        window.contentView = glass

        let content = glass.contentView
        content.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: L.t("Языки", "Languages"))
        header.font = DS.Font.text(13, weight: .semibold)
        header.textColor = DS.Color.textPrimary
        header.translatesAutoresizingMaskIntoConstraints = false

        let autoLabel = NSTextField(labelWithString: L.t("Автоопределение", "Auto-detect"))
        autoLabel.font = DS.Font.text(11.5, weight: .medium)
        autoLabel.textColor = DS.Color.textSecondary
        autoLabel.translatesAutoresizingMaskIntoConstraints = false

        autoSwitch.state = autoDetect ? .on : .off
        autoSwitch.target = self
        autoSwitch.action = #selector(autoSwitchChanged)
        autoSwitch.controlSize = .small
        autoSwitch.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = L.t("Поиск языка…", "Search…")
        searchField.font = DS.Font.text(12, weight: .regular)
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.spacing = 2
        listStack.translatesAutoresizingMaskIntoConstraints = false

        let clip = FlippedView()
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(listStack)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = clip

        primaryHint.font = DS.Font.text(11, weight: .regular)
        primaryHint.textColor = DS.Color.textTertiary
        primaryHint.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = StyledButton(
            title: L.t("Готово", "Done"),
            style: .primary, action: #selector(saveTapped), target: self)
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        [header, autoLabel, autoSwitch, searchField, scroll, primaryHint, saveButton]
            .forEach { content.addSubview($0) }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),

            autoSwitch.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            autoSwitch.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            autoLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            autoLabel.trailingAnchor.constraint(equalTo: autoSwitch.leadingAnchor, constant: -6),

            searchField.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: 26),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: primaryHint.topAnchor, constant: -8),

            clip.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            clip.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            clip.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            clip.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            listStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: clip.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: clip.bottomAnchor),

            primaryHint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            primaryHint.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),

            saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        ])
    }

    private func rebuildList(filter: String) {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? items : items.filter {
            $0.title.lowercased().contains(q) || $0.native.lowercased().contains(q) || $0.code.contains(q)
        }
        // Выбранные — наверх, в порядке выбора (первый = основной).
        let selected = selectedCodes.compactMap { code in filtered.first { $0.code == code } }
        let rest = filtered.filter { !selectedCodes.contains($0.code) }
        for item in (selected + rest) {
            let isSelected = selectedCodes.contains(item.code)
            let isPrimary = !autoDetect && item.code == selectedCodes.first
            let row = MultiPickerRow(
                title: item.title, native: item.native,
                selected: isSelected, isPrimary: isPrimary
            ) { [weak self] in self?.toggle(item.code) }
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
    }

    private func toggle(_ code: String) {
        if let idx = selectedCodes.firstIndex(of: code) {
            selectedCodes.remove(at: idx)
        } else {
            selectedCodes.append(code)
        }
        rebuildList(filter: searchField.stringValue)
        updatePrimaryHint()
    }

    private func updatePrimaryHint() {
        if autoDetect {
            primaryHint.stringValue = L.t("Язык определяется автоматически", "Language detected automatically")
        } else if let first = selectedCodes.first,
                  let item = items.first(where: { $0.code == first }) {
            primaryHint.stringValue = L.t("Основной: ", "Primary: ") + item.title
        } else {
            primaryHint.stringValue = L.t("Выберите хотя бы один язык", "Select at least one language")
        }
    }

    @objc private func autoSwitchChanged() {
        autoDetect = autoSwitch.state == .on
        rebuildList(filter: searchField.stringValue)
        updatePrimaryHint()
    }

    @objc private func saveTapped() { saveAndDismiss() }

    func controlTextDidChange(_ obj: Notification) {
        rebuildList(filter: searchField.stringValue)
    }
}

/// Строка мультивыбора языка: название + самоназвание + галочка; бейдж «основной».
@MainActor
private final class MultiPickerRow: NSView {
    private let onToggle: () -> Void
    private var trackingArea: NSTrackingArea?
    private var hovering = false
    private let selected: Bool

    init(title: String, native: String, selected: Bool, isPrimary: Bool, onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        self.selected = selected
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = DS.Font.text(12.5, weight: selected ? .semibold : .regular)
        titleLabel.textColor = selected ? .white : DS.Color.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let nativeLabel = NSTextField(labelWithString: native)
        nativeLabel.font = DS.Font.text(11, weight: .regular)
        nativeLabel.textColor = DS.Color.textTertiary
        nativeLabel.translatesAutoresizingMaskIntoConstraints = false

        let check = NSImageView()
        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        check.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        check.contentTintColor = DS.Color.accent
        check.isHidden = !selected
        check.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(nativeLabel)
        addSubview(check)

        var constraints: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: 34),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nativeLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            nativeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            check.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]

        if isPrimary {
            let badge = NSTextField(labelWithString: L.t("основной", "primary"))
            badge.font = DS.Font.text(10, weight: .semibold)
            badge.textColor = DS.Color.accent
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            constraints.append(badge.trailingAnchor.constraint(equalTo: check.leadingAnchor, constant: -10))
            constraints.append(badge.centerYAnchor.constraint(equalTo: centerYAnchor))
        }

        NSLayoutConstraint.activate(constraints)
        updateBackground()
    }

    required init?(coder: NSCoder) { nil }

    private func updateBackground() {
        let color = selected
            ? DS.Color.accent.withAlphaComponent(0.16)
            : NSColor.white.withAlphaComponent(hovering ? 0.10 : 0.0)
        layer?.backgroundColor = color.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateBackground() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateBackground() }
    override func mouseDown(with event: NSEvent) { onToggle() }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
