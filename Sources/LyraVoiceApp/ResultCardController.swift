import AppKit
import LyraVoiceCore

/// Плавающая карточка результата: показывается, когда автовставка невозможна
/// (курсор не в поле ввода или нет Accessibility). Показывает надиктованный текст
/// и кнопку «Скопировать», авто-закрывается через несколько секунд.
/// Аналог «Select a textbox first, then dictate» у Aqua/Superwhisper.
@MainActor
final class ResultCardController {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?
    private let cardView = ResultCardView()
    private let cardWidth: CGFloat = 380
    /// Через сколько секунд карточка закроется сама. Кольцо-таймер на крестике
    /// визуализирует этот обратный отсчёт, чтобы окно не висело постоянно.
    private static let autoDismissSeconds: TimeInterval = 15

    var onCopy: ((String) -> Void)?
    private var currentText = ""

    func show(text: String, hint: String) {
        currentText = text
        let panel = self.panel ?? makePanel()
        cardView.configure(text: text, hint: hint)

        let height = cardView.heightThatFits(width: cardWidth)
        panel.setContentSize(NSSize(width: cardWidth, height: height))
        place(panel)
        panel.orderFrontRegardless()
        self.panel = panel
        scheduleDismiss(after: Self.autoDismissSeconds)
        cardView.startCountdown(duration: Self.autoDismissSeconds)
    }

    func hide() {
        dismissWork?.cancel()
        dismissWork = nil
        cardView.stopCountdown()
        panel?.orderOut(nil)
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: cardWidth, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = cardView
        cardView.onClose = { [weak self] in self?.hide() }
        cardView.onCopy = { [weak self] in
            guard let self else { return }
            self.onCopy?(self.currentText)
            self.hide()
        }
        return panel
    }

    private func place(_ panel: NSPanel) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let x = screen.midX - panel.frame.width / 2
        let y = screen.minY + 44
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Вью карточки результата

@MainActor
final class ResultCardView: NSView {
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?

    private let glass = DS.makeGlassContainer(cornerRadius: 22)
    private let iconView = NSImageView()
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private let closeButton = ResultCloseButton()
    private var copyButton: StyledButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(glass)
        glass.translatesAutoresizingMaskIntoConstraints = false

        let content = glass.contentView
        content.translatesAutoresizingMaskIntoConstraints = false

        iconView.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.contentTintColor = DS.Color.textSecondary
        iconView.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.font = DS.Font.text(12)
        hintLabel.textColor = DS.Color.textTertiary
        hintLabel.maximumNumberOfLines = 1
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        textLabel.font = DS.Font.text(14)
        textLabel.textColor = DS.Color.textPrimary
        textLabel.maximumNumberOfLines = 4
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.onClick = { [weak self] in self?.onClose?() }

        copyButton = StyledButton(title: L.t("Скопировать", "Copy"), style: .secondary, action: #selector(copyTapped), target: self)
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(iconView)
        content.addSubview(hintLabel)
        content.addSubview(closeButton)
        content.addSubview(textLabel)
        content.addSubview(copyButton)

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            iconView.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            iconView.widthAnchor.constraint(equalToConstant: 18),

            hintLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            hintLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -10),

            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            closeButton.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            textLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            textLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            textLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 14),

            copyButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            copyButton.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 16),
            copyButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(text: String, hint: String) {
        textLabel.stringValue = text
        hintLabel.stringValue = hint
        needsLayout = true
    }

    /// Высота карточки под заданную ширину (для размера панели). На macOS
    /// `fittingSize` учитывает перенос текста, если ширину зафиксировать.
    func heightThatFits(width: CGFloat) -> CGFloat {
        let widthConstraint = widthAnchor.constraint(equalToConstant: width)
        widthConstraint.isActive = true
        textLabel.preferredMaxLayoutWidth = width - 36   // паддинги 18+18
        layoutSubtreeIfNeeded()
        let height = fittingSize.height
        widthConstraint.isActive = false
        return max(120, height)
    }

    @objc private func copyTapped() { onCopy?() }

    /// Запускает кольцо-таймер обратного отсчёта на кнопке закрытия.
    func startCountdown(duration: TimeInterval) { closeButton.startCountdown(duration: duration) }
    /// Останавливает и сбрасывает кольцо (при закрытии / переиспользовании карточки).
    func stopCountdown() { closeButton.stopCountdown() }
}

/// Круглая кнопка-крестик закрытия с кольцом обратного отсчёта по краю: пока идёт
/// таймер авто-закрытия, кольцо «убывает» от полного до нуля, по завершении
/// карточка закрывается сама. Так окно не висит на экране постоянно.
@MainActor
private final class ResultCloseButton: NSView {
    var onClick: (() -> Void)?
    private let imageView = NSImageView()
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let ringWidth: CGFloat = 2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor

        for ring in [trackLayer, progressLayer] {
            ring.fillColor = NSColor.clear.cgColor
            ring.lineWidth = ringWidth
            ring.lineCap = .round
            layer?.addSublayer(ring)
        }
        trackLayer.strokeColor = NSColor.white.withAlphaComponent(0.14).cgColor
        progressLayer.strokeColor = NSColor.white.withAlphaComponent(0.70).cgColor
        progressLayer.strokeEnd = 1

        imageView.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: L.t("Закрыть", "Close"))
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        imageView.contentTintColor = DS.Color.textSecondary
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2     // круглая кнопка под круговое кольцо
        layer?.cornerCurve = .continuous

        // Кольцо по краю кнопки: старт сверху (12 часов), по часовой стрелке.
        let inset = ringWidth / 2 + 0.5
        let radius = min(bounds.width, bounds.height) / 2 - inset
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius,
                    startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for ring in [trackLayer, progressLayer] {
            ring.frame = bounds
            ring.path = path
        }
    }

    /// Кольцо стартует полным и линейно убывает до нуля за `duration` — синхронно
    /// с таймером авто-закрытия в контроллере (кольцо здесь только визуальное).
    func startCountdown(duration: TimeInterval) {
        progressLayer.removeAnimation(forKey: "countdown")
        let anim = CABasicAnimation(keyPath: "strokeEnd")
        anim.fromValue = 1.0
        anim.toValue = 0.0
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        progressLayer.add(anim, forKey: "countdown")
    }

    func stopCountdown() {
        progressLayer.removeAnimation(forKey: "countdown")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = 1
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}
