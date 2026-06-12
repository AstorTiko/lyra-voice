import AppKit
import LyraVoiceCore

/// Первичный онбординг в стиле Aqua Voice / Superwhisper, но в НАШЕМ тёмном
/// Liquid Glass: Welcome → Микрофон → Авто-вставка → Готово. Каждый шаг с крупной
/// иконкой, понятным текстом и одной кнопкой действия; статус прав обновляется
/// вживую (таймером), чтобы галочка загоралась, как только доступ выдан.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    private enum Step: Int, CaseIterable {
        case welcome, microphone, accessibility, ready
    }

    /// completed=true в обоих случаях (закрытие крестиком тоже считаем «прошёл»).
    var onFinish: ((_ completed: Bool) -> Void)?

    private var step: Step = .welcome
    private let hotkeyText: String
    private var statusTimer: Timer?
    private var didFinish = false

    private let backdrop = NSView()
    private let logoImageView = NSImageView()
    private let progressStack = NSStackView()
    private var dots: [NSView] = []
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private var actionButton: StyledButton!
    private var backButton: StyledButton!
    private var nextButton: StyledButton!

    init(hotkeyText: String, onFinish: ((Bool) -> Void)? = nil) {
        self.hotkeyText = hotkeyText
        self.onFinish = onFinish

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.isReleasedWhenClosed = false
        window.center()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        super.init(window: window)
        window.delegate = self
        buildUI()
        renderStep()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        // Политику активации (Dock vs только меню) задаёт AppDelegate по настройке.
        NSApp.unhide(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        startStatusTimer()
    }

    // MARK: - UI

    private func buildUI() {
        guard let window else { return }

        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = DS.Color.base.cgColor
        window.contentView = backdrop

        logoImageView.image = BrandAssets.logoImage(size: 46)
        logoImageView.imageScaling = .scaleProportionallyUpOrDown

        progressStack.orientation = .horizontal
        progressStack.spacing = 8
        progressStack.alignment = .centerY
        for _ in Step.allCases {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
            dots.append(dot)
            progressStack.addArrangedSubview(dot)
        }

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = DS.Color.accent

        titleLabel.font = DS.Font.display(24, weight: .semibold)
        titleLabel.textColor = DS.Color.textPrimary
        titleLabel.alignment = .center

        bodyLabel.font = DS.Font.text(14)
        bodyLabel.textColor = DS.Color.textSecondary
        bodyLabel.alignment = .center
        bodyLabel.preferredMaxLayoutWidth = 420
        bodyLabel.maximumNumberOfLines = 0

        statusLabel.font = DS.Font.text(13, weight: .medium)
        statusLabel.alignment = .center

        actionButton = StyledButton(title: "", style: .secondary, action: #selector(doAction), target: self)
        backButton = StyledButton(title: L.t("Назад", "Back"), style: .ghost, action: #selector(goBack), target: self)
        nextButton = StyledButton(title: L.t("Далее", "Next"), style: .primary, action: #selector(goNext), target: self)

        let centerStack = NSStackView(views: [iconView, titleLabel, bodyLabel, statusLabel, actionButton])
        centerStack.orientation = .vertical
        centerStack.alignment = .centerX
        centerStack.spacing = 16
        centerStack.setCustomSpacing(20, after: iconView)
        centerStack.setCustomSpacing(20, after: bodyLabel)

        let chrome: [NSView] = [logoImageView, progressStack, centerStack, backButton, nextButton]
        for view in chrome {
            view.translatesAutoresizingMaskIntoConstraints = false
            backdrop.addSubview(view)
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            logoImageView.centerXAnchor.constraint(equalTo: backdrop.centerXAnchor),
            logoImageView.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 30),
            logoImageView.widthAnchor.constraint(equalToConstant: 46),
            logoImageView.heightAnchor.constraint(equalToConstant: 46),

            progressStack.centerXAnchor.constraint(equalTo: backdrop.centerXAnchor),
            progressStack.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 16),

            centerStack.centerXAnchor.constraint(equalTo: backdrop.centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: backdrop.centerYAnchor, constant: 16),
            centerStack.widthAnchor.constraint(equalToConstant: 440),

            iconView.widthAnchor.constraint(equalToConstant: 60),
            iconView.heightAnchor.constraint(equalToConstant: 60),

            backButton.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 28),
            backButton.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -26),

            nextButton.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -28),
            nextButton.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -26),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])
    }

    // MARK: - Рендер шага

    private func renderStep() {
        for (index, dot) in dots.enumerated() {
            dot.layer?.backgroundColor = (index == step.rawValue
                ? DS.Color.accent.cgColor
                : NSColor.white.withAlphaComponent(0.16).cgColor)
        }

        iconView.image = symbol(for: step)
        backButton.isHidden = (step == .welcome)

        switch step {
        case .welcome:
            titleLabel.stringValue = L.t("Добро пожаловать в \(AppBrand.displayName)", "Welcome to \(AppBrand.displayName)")
            bodyLabel.stringValue = L.t(
                "Голос в текст в любом приложении: нажми хоткей, говори — текст распознаётся локально и сам вставляется. Настроим за минуту.",
                "Voice to text in any app: press the hotkey, speak — your words are transcribed locally and pasted automatically. Set up in a minute.")
            actionButton.isHidden = true
            statusLabel.isHidden = true
            nextButton.title = L.t("Начать", "Get started")
        case .microphone:
            titleLabel.stringValue = L.t("Доступ к микрофону", "Microphone access")
            bodyLabel.stringValue = L.t(
                "Нужен, чтобы записывать твою речь. Запись и распознавание идут локально на этом Mac — ничего не уходит в облако.",
                "Needed to record your speech. Recording and transcription happen locally on this Mac — nothing leaves for the cloud.")
            actionButton.isHidden = false
            actionButton.title = L.t("Разрешить микрофон", "Allow microphone")
            statusLabel.isHidden = false
            nextButton.title = L.t("Далее", "Next")
        case .accessibility:
            titleLabel.stringValue = L.t("Авто-вставка текста", "Auto-paste text")
            bodyLabel.stringValue = L.t(
                "Доступ к универсальному управлению (Accessibility) позволяет вставлять распознанный текст прямо в активное поле. Без него текст просто копируется в буфер.",
                "Accessibility access lets the app paste transcribed text straight into the active field. Without it, text is just copied to the clipboard.")
            actionButton.isHidden = false
            actionButton.title = L.t("Разрешить авто-вставку", "Allow auto-paste")
            statusLabel.isHidden = false
            nextButton.title = L.t("Далее", "Next")
        case .ready:
            titleLabel.stringValue = L.t("Всё готово", "All set")
            bodyLabel.stringValue = L.t(
                "Нажми «\(hotkeyText)» в любом приложении и говори. Остановишь — текст причешется и вставится. Хоткей, модель и полировку можно изменить в настройках.",
                "Press “\(hotkeyText)” in any app and speak. Stop, and the text is polished and pasted. You can change the hotkey, model and polishing in settings.")
            actionButton.isHidden = true
            statusLabel.isHidden = true
            nextButton.title = L.t("Готово", "Done")
        }

        refreshStatus()
    }

    private func symbol(for step: Step) -> NSImage? {
        let name: String
        switch step {
        case .welcome: name = "sparkles"
        case .microphone: name = "mic.fill"
        case .accessibility: name = "cursorarrow.click.2"
        case .ready: name = "checkmark.seal.fill"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 52, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    /// Обновляет «галочку» статуса прав на шаге, не перерисовывая весь экран.
    private func refreshStatus() {
        switch step {
        case .microphone:
            let granted = MicrophonePermission.statusDescription.contains("granted")
                || MicrophonePermission.statusDescription.contains("authorized")
            setStatus(granted: granted, grantedText: L.t("Микрофон разрешён", "Microphone allowed"), pendingText: L.t("Пока нет доступа", "Not granted yet"))
            actionButton.isEnabled = !granted
        case .accessibility:
            let trusted = AccessibilityPermission.isTrusted
            setStatus(granted: trusted, grantedText: L.t("Авто-вставка разрешена", "Auto-paste allowed"), pendingText: L.t("Пока нет доступа", "Not granted yet"))
            actionButton.isEnabled = !trusted
        default:
            break
        }
    }

    private func setStatus(granted: Bool, grantedText: String, pendingText: String) {
        statusLabel.stringValue = granted ? "✓ \(grantedText)" : pendingText
        statusLabel.textColor = granted ? DS.Color.success : DS.Color.textTertiary
    }

    private func startStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    // MARK: - Действия

    @objc private func doAction() {
        switch step {
        case .microphone:
            Task {
                _ = await MicrophonePermission.requestIfNeeded()
                refreshStatus()
                // Если ранее отказали — системный диалог не покажется, ведём в настройки.
                if MicrophonePermission.statusDescription.contains("denied") {
                    MicrophonePermission.openSystemSettings()
                }
            }
        case .accessibility:
            if !AccessibilityPermission.isTrusted {
                _ = AccessibilityPermission.requestIfNeeded()
                AccessibilityPermission.openSystemSettings()
            }
            refreshStatus()
        default:
            break
        }
    }

    @objc private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
        renderStep()
    }

    @objc private func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
        renderStep()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        statusTimer?.invalidate()
        statusTimer = nil
        onFinish?(true)
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        statusTimer?.invalidate()
        statusTimer = nil
        guard !didFinish else { return }
        didFinish = true
        onFinish?(true)
    }
}
