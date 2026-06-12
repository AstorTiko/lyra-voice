import AppKit
import LyraVoiceCore

@MainActor
protocol OverlayViewDelegate: AnyObject {
    func overlayViewDidAccept()
    func overlayViewDidCancel()
}

enum OverlayPresentationMode: Equatable {
    case pushToTalk
    case toggle
}

/// Системный overlay записи.
/// Два режима отображения:
/// - Pill (recording / processing / status): компактная тёмная капсула с brand-gradient волной.
/// - Streaming panel: расширенная капсула с живым текстом, brand accent-линией и статус-баром.
@MainActor
final class OverlayView: NSView {
    weak var delegate: OverlayViewDelegate?

    private var mode: OverlayPresentationMode = .toggle

    /// В состояниях обработки/статуса кнопок нет — волна (и её bloom) занимает ВЕСЬ фрейм
    /// капсулы, а не узкую зону между кнопками. Управляет раскладкой в `layoutPill`.
    private var fullFrameWave = false

    /// Геометрия стриминг-панели — общие константы для layout и расчёта хвоста текста,
    /// чтобы fittingTail точно совпадал с реальной зоной liveTextLabel.
    private enum StreamLayout {
        static let barHeight: CGFloat = 28
        static let accentWidth: CGFloat = 3
        static let textLeftGap: CGFloat = 14
        static let textRightPad: CGFloat = 16
        static let textPadV: CGFloat = 12
    }

    // MARK: - Pill (recording / processing / status)

    private let glass = DS.makeGlassContainer(cornerRadius: CGFloat(OverlayMetrics.cornerRadius), style: .overlay)
    private let waveform = WaveformView()
    private let cancelButton = CircleIconButton(
        symbolName: "xmark",
        background: NSColor.white.withAlphaComponent(0.10),
        foreground: NSColor.white.withAlphaComponent(0.70),
        pointSize: 8, weight: .semibold
    )
    private let acceptButton = CircleIconButton(
        symbolName: "checkmark",
        background: NSColor.white.withAlphaComponent(0.92),
        foreground: NSColor(white: 0.08, alpha: 1),
        pointSize: 9, weight: .bold
    )

    // MARK: - Streaming panel

    private let streamingContainer = NSView()

    // Accent line слева: градиент violet → cyan
    private let accentLineView: NSView = {
        let v = NSView(); v.wantsLayer = true; return v
    }()
    private var accentGradientLayer: CAGradientLayer?

    // Live text
    private let liveTextLabel: NSTextField = {
        let f = NSTextField()
        f.isEditable = false; f.isBordered = false; f.drawsBackground = false
        f.backgroundColor = .clear
        f.textColor = .white
        f.font = DS.Font.text(12.5, weight: .medium)
        f.maximumNumberOfLines = 3
        f.lineBreakMode = .byWordWrapping
        f.cell?.truncatesLastVisibleLine = true
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return f
    }()

    // Separator
    private let separatorView: NSView = {
        let v = NSView(); v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        return v
    }()

    // Bottom bar
    private let bottomBarView = NSView()

    private let streamCancelButton = CircleIconButton(
        symbolName: "xmark",
        background: NSColor.white.withAlphaComponent(0.10),
        foreground: NSColor.white.withAlphaComponent(0.70),
        pointSize: 7, weight: .semibold
    )
    private let streamStopButton = CircleIconButton(
        symbolName: "stop.fill",
        background: NSColor.white.withAlphaComponent(0.92),
        foreground: NSColor(white: 0.08, alpha: 1),
        pointSize: 8, weight: .bold
    )

    // Пульсирующая точка «слушаю»
    private let listeningDotView: NSView = {
        let v = NSView(); v.wantsLayer = true
        v.layer?.backgroundColor = DS.Color.accentCyan.cgColor
        return v
    }()

    private let targetAppLabel: NSTextField = {
        let f = NSTextField()
        f.isEditable = false; f.isBordered = false; f.drawsBackground = false
        f.backgroundColor = .clear
        f.textColor = DS.Color.accentCyan
        f.font = DS.Font.text(10.5, weight: .medium)
        f.lineBreakMode = .byTruncatingTail; f.maximumNumberOfLines = 1
        return f
    }()

    private let micNameLabel: NSTextField = {
        let f = NSTextField()
        f.isEditable = false; f.isBordered = false; f.drawsBackground = false
        f.backgroundColor = .clear
        f.textColor = DS.Color.textTertiary
        f.font = DS.Font.text(10, weight: .regular)
        f.lineBreakMode = .byTruncatingTail; f.maximumNumberOfLines = 1
        f.alignment = .right
        return f
    }()

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        // Pill
        addSubview(glass)
        glass.contentView.addSubview(waveform)
        glass.contentView.addSubview(cancelButton)
        glass.contentView.addSubview(acceptButton)

        acceptButton.toolTip = L.t("Завершить и вставить", "Finish and paste")
        cancelButton.toolTip = L.t("Отменить", "Cancel")
        cancelButton.onClick = { [weak self] in self?.delegate?.overlayViewDidCancel() }
        acceptButton.onClick = { [weak self] in self?.delegate?.overlayViewDidAccept() }

        // Streaming panel — поверх glass (glass остаётся фоном)
        streamingContainer.isHidden = true
        glass.contentView.addSubview(streamingContainer)

        setupStreamingPanel()
        setupAccentLine()
        scheduleListeningDotPulse()

        render(state: .recording(seconds: 0, level: 0.2))
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Streaming panel setup

    private func setupStreamingPanel() {
        streamingContainer.wantsLayer = true
        streamingContainer.layer?.backgroundColor = NSColor.clear.cgColor

        [accentLineView, liveTextLabel, separatorView, bottomBarView].forEach {
            streamingContainer.addSubview($0)
        }
        [streamCancelButton, listeningDotView, targetAppLabel, micNameLabel, streamStopButton].forEach {
            bottomBarView.addSubview($0)
        }

        streamCancelButton.onClick = { [weak self] in self?.delegate?.overlayViewDidCancel() }
        streamStopButton.onClick = { [weak self] in self?.delegate?.overlayViewDidAccept() }
        streamCancelButton.toolTip = L.t("Отменить", "Cancel")
        streamStopButton.toolTip = L.t("Завершить и вставить", "Finish and paste")
    }

    private func setupAccentLine() {
        accentLineView.wantsLayer = true
        let g = CAGradientLayer()
        g.type = .axial
        // Violet вверху → cyan внизу (CA координаты: y=1 = верх слоя)
        g.startPoint = CGPoint(x: 0.5, y: 1)
        g.endPoint = CGPoint(x: 0.5, y: 0)
        g.colors = [DS.Color.accentViolet.cgColor, DS.Color.accentCyan.cgColor]
        g.cornerRadius = 1.5
        accentLineView.layer?.addSublayer(g)
        accentGradientLayer = g
    }

    private func scheduleListeningDotPulse() {
        listeningDotView.wantsLayer = true
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.35
        pulse.toValue = 1.0
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        listeningDotView.layer?.add(pulse, forKey: "pulse")
    }

    // MARK: - Public API

    func setMode(_ mode: OverlayPresentationMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        needsLayout = true
    }

    func render(state: OverlayState) {
        if case let .streaming(text, targetApp, micName) = state {
            // Показываем streaming panel, скрываем pill-содержимое
            waveform.isHidden = true
            cancelButton.isHidden = true
            acceptButton.isHidden = true
            streamingContainer.isHidden = false
            updateStreamingContent(text: text, targetApp: targetApp, micName: micName)
        } else {
            // Показываем pill, скрываем streaming panel
            waveform.isHidden = false
            streamingContainer.isHidden = true
            switch state {
            case let .recording(_, level):
                fullFrameWave = false
                waveform.setRecording(level: level)
                hidePillButtons()
            case .processing:
                fullFrameWave = true
                waveform.setProcessing()
                hidePillButtons()
            case .inserted:
                fullFrameWave = true
                waveform.setStatus(color: DS.Color.success)
                hidePillButtons()
            case .copied:
                fullFrameWave = true
                waveform.setStatus(color: DS.Color.info)
                hidePillButtons()
            case .error:
                fullFrameWave = true
                waveform.setStatus(color: DS.Color.danger)
                hidePillButtons()
            case .streaming:
                break
            }
            needsLayout = true
        }
    }

    /// Лёгкое обновление уровня волны (вызывается часто во время записи). Не трогает
    /// структуру/видимость — только передаёт уровень в WaveformView (его 30fps-таймер
    /// сам плавно анимирует бары). Когда показана streaming-панель — no-op.
    func updateWaveformLevel(_ level: Double) {
        guard !waveform.isHidden else { return }
        waveform.updateLevel(level)
    }

    private func hidePillButtons() {
        cancelButton.isHidden = true
        acceptButton.isHidden = true
    }

    private func updateStreamingContent(text: String, targetApp: String?, micName: String?) {
        // Growing-window ASR отдаёт текст С НАЧАЛА записи и он всё растёт. Показываем
        // ХВОСТ (последние слова), влезающий в 3 строки, иначе панель «залипает» на
        // первой фразе и новые слова не видно.
        liveTextLabel.stringValue = text.isEmpty ? L.t("Слушаю...", "Listening...") : fittingTail(text)
        // Нижняя строка показывает целевое приложение. Если оно неизвестно — пусто (раньше
        // была заглушка «→ Слушаю», которая дублировала текст и висела слева у кнопки отмены).
        targetAppLabel.stringValue = targetApp.map { "→ \($0)" } ?? ""
        micNameLabel.stringValue = micName ?? L.t("Микрофон", "Microphone")
        needsLayout = true
    }

    /// Возвращает максимальный по длине ХВОСТ текста, влезающий в высоту liveTextLabel
    /// (3 строки). Если текст обрезан с начала — добавляет «…». Размеры берём из констант
    /// стриминг-панели, а не из frame: на первом тике layout ещё мог не сработать.
    private func fittingTail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let maxW = CGFloat(OverlayMetrics.streamingSize.width)
            - StreamLayout.accentWidth - StreamLayout.textLeftGap - StreamLayout.textRightPad
        let maxH = CGFloat(OverlayMetrics.streamingSize.height)
            - StreamLayout.barHeight - StreamLayout.textPadV * 2
        guard maxW > 1, maxH > 1 else { return trimmed }

        if measuredTextHeight(trimmed, width: maxW) <= maxH + 0.5 { return trimmed }

        // Отбрасываем слова с начала, пока хвост (с «…») не влезет в высоту метки.
        var words = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while words.count > 1 {
            words.removeFirst()
            let candidate = "… " + words.joined(separator: " ")
            if measuredTextHeight(candidate, width: maxW) <= maxH + 0.5 { return candidate }
        }
        return "… " + (words.last ?? "")
    }

    /// Высота, которую займёт строка `s` в `liveTextLabel` при ширине `width`.
    /// Один источник правды и для `fittingTail` (обрезка хвоста), и для layout (высота рамки).
    private func measuredTextHeight(_ s: String, width: CGFloat) -> CGFloat {
        guard width > 1 else { return 0 }
        let font = liveTextLabel.font ?? DS.Font.text(12.5, weight: .medium)
        let str = s.isEmpty ? " " : s
        return NSAttributedString(string: str, attributes: [.font: font])
            .boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            .height
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        glass.frame = bounds
        // Стекло лэйаутит свой contentView отдельным проходом. При анимированном росте окна
        // contentView.bounds к этому моменту ещё СТАРЫЙ (маленький) → стриминг-панель
        // раскладывалась в крошечной зоне внизу (текст «Слушаю» и кнопки прижаты к низу-слева).
        // Форсируем синхронный лэйаут стекла, чтобы contentView.bounds был актуальным.
        glass.layoutSubtreeIfNeeded()

        if !streamingContainer.isHidden {
            layoutStreamingPanel()
        } else {
            layoutPill()
        }
    }

    private func layoutPill() {
        let h = bounds.height
        let btn = CGFloat(OverlayMetrics.buttonSize)
        let edge: CGFloat = 4

        // Обработка/статус: кнопок нет → волна и её bloom занимают весь фрейм капсулы.
        if fullFrameWave {
            waveform.frame = NSRect(x: 0, y: 0, width: bounds.width, height: h)
            streamingContainer.frame = glass.contentView.bounds
            return
        }

        switch mode {
        case .pushToTalk:
            let inset: CGFloat = 10
            waveform.frame = NSRect(x: inset, y: 0, width: bounds.width - inset * 2, height: h)
        case .toggle:
            if cancelButton.isHidden && acceptButton.isHidden {
                let inset: CGFloat = 13
                waveform.frame = NSRect(x: inset, y: 0, width: bounds.width - inset * 2, height: h)
            } else {
                cancelButton.frame = NSRect(x: edge, y: (h - btn) / 2, width: btn, height: btn)
                acceptButton.frame = NSRect(x: bounds.width - btn - edge, y: (h - btn) / 2, width: btn, height: btn)
                let gap: CGFloat = 7
                let waveX = cancelButton.frame.maxX + gap
                let waveW = acceptButton.frame.minX - gap - waveX
                waveform.frame = NSRect(x: waveX, y: 0, width: max(0, waveW), height: h)
            }
        }

        streamingContainer.frame = glass.contentView.bounds
    }

    private func layoutStreamingPanel() {
        let totalW = glass.contentView.bounds.width
        let totalH = glass.contentView.bounds.height
        streamingContainer.frame = glass.contentView.bounds

        let barH = StreamLayout.barHeight
        let accentW = StreamLayout.accentWidth
        let textAreaH: CGFloat = totalH - barH

        // Accent line: левый край, только зона текста
        accentLineView.frame = NSRect(x: 0, y: barH, width: accentW, height: textAreaH)
        accentGradientLayer?.frame = accentLineView.bounds

        // Text label: правее accent line, с воздухом сверху и справа.
        // Высоту рамки подгоняем под ФАКТИЧЕСКИЙ текст и пришпиливаем к ВЕРХУ зоны текста —
        // строки растут вниз (как при чтении). Иначе NSTextField в высокой рамке выравнивал
        // одиночную строку «Слушаю» неоднозначно и срезал её по базовой линии (см. скриншот).
        let textPadV = StreamLayout.textPadV
        let textX = accentW + StreamLayout.textLeftGap
        let textW = totalW - accentW - StreamLayout.textLeftGap - StreamLayout.textRightPad
        let availH = textAreaH - textPadV * 2
        let textTop = totalH - textPadV                      // верхняя внутренняя кромка зоны текста
        let measured = min(availH, ceil(measuredTextHeight(liveTextLabel.stringValue, width: textW)) + 2)
        liveTextLabel.frame = NSRect(x: textX, y: textTop - measured, width: textW, height: measured)

        // Separator
        separatorView.frame = NSRect(x: 0, y: barH - 0.5, width: totalW, height: 0.5)

        // Bottom bar
        bottomBarView.frame = NSRect(x: 0, y: 0, width: totalW, height: barH)

        let btnS: CGFloat = 20
        let edgeX: CGFloat = 8
        let centerY = (barH - btnS) / 2

        streamCancelButton.frame = NSRect(x: edgeX, y: centerY, width: btnS, height: btnS)
        streamStopButton.frame = NSRect(x: totalW - edgeX - btnS, y: centerY, width: btnS, height: btnS)

        // Пульсирующая точка
        let dotS: CGFloat = 7
        let dotX = streamCancelButton.frame.maxX + 8
        listeningDotView.layer?.cornerRadius = dotS / 2
        listeningDotView.frame = NSRect(x: dotX, y: (barH - dotS) / 2, width: dotS, height: dotS)

        // Лейблы статуса вертикально центрируем в нижней полосе (NSTextField иначе
        // прижимает текст вверх — отсюда «кривые» отступы).
        let labelH: CGFloat = 14
        let labelY = (barH - labelH) / 2
        let midX = totalW / 2

        // Target app label: от точки до середины.
        let dotRight = listeningDotView.frame.maxX + 6
        targetAppLabel.frame = NSRect(x: dotRight, y: labelY, width: max(0, midX - dotRight), height: labelH)

        // Mic label: от середины до stop button, выровнена вправо.
        let micRight = streamStopButton.frame.minX - 6
        micNameLabel.frame = NSRect(x: midX, y: labelY, width: max(0, micRight - midX), height: labelH)
    }
}

// MARK: - WaveformView (brand gradient bars + Siri-style processing)

/// Минималистичная аудиоволна с brand-градиентом Lyra Voice.
/// Запись: вертикальные полоски с gradient violet→cyan (короткие = фиолетовые, высокие = cyan-акцент).
/// Обработка: Siri/Apple-Intelligence-стиль под наш бренд — поток градиента по кромке капсулы.
@MainActor
private final class WaveformView: NSView {
    private enum Phase {
        case recording
        case processing
        case status(NSColor)
    }

    private var bars: [CAGradientLayer] = []
    private var heights: [CGFloat] = []
    private var buffer: [CGFloat] = []
    private var currentLevel: CGFloat = 0.04
    private var recordingIsIdle = true
    private var phase: Phase = .recording
    private var timer: Timer?

    /// Фаза бегущей звуковой волны в режиме обработки (растёт каждый тик).
    private var processingPhase: CGFloat = 0

    /// Слои светящейся обводки в стиле Siri (поток градиента по кромке капсулы).
    private var processingRimLayers: [CALayer] = []

    private let barWidth: CGFloat = 2
    private let barGap: CGFloat = 2.5
    private let minBar: CGFloat = 2
    private let idleLevel: CGFloat = 0
    private let noiseGate: CGFloat = 0.10
    private let voiceGain: CGFloat = 1.35

    /// Отступ звуковой волны от краёв капсулы. В обработке волна сжата к ЦЕНТРУ, чтобы
    /// не касаться светящейся обводки; в записи — во всю ширину зоны.
    private var waveInsetX: CGFloat {
        if case .processing = phase { return max(bounds.height * 0.75, 14) }
        return 0
    }
    private var waveInsetY: CGFloat {
        if case .processing = phase { return 7 }
        return 6
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { nil }

    // MARK: Фазы

    func setRecording(level: Double) {
        phase = .recording
        applyRecordingLevel(level)
        removeProcessingRim()
        bars.forEach { bar in
            applyRecordingGradient(bar)
            applyGlow(bar, on: false)
        }
        startTimer()
    }

    /// Лёгкое обновление: только меняем целевой уровень. Плавную анимацию баров делает
    /// собственный 30fps-таймер. Вызывается часто — здесь не должно быть тяжёлой работы.
    func updateLevel(_ level: Double) {
        guard case .recording = phase else { return }
        applyRecordingLevel(level)
    }

    private func applyRecordingLevel(_ level: Double) {
        let clamped = CGFloat(max(0, min(level, 1.0)))
        guard clamped >= noiseGate else {
            recordingIsIdle = true
            currentLevel = idleLevel
            renderIdleDots(animated: true)
            return
        }
        recordingIsIdle = false
        let normalized = min(1.0, max(0, (clamped - noiseGate) / (1 - noiseGate)))
        currentLevel = min(1.0, max(0.18, sqrt(normalized) * voiceGain))
    }

    /// Обработка: светящаяся обводка в стиле Siri по кромке капсулы (поток бренд-градиента)
    /// + неоновая звуковая волна в ЦЕНТРЕ, не касающаяся обводки. Бары «текут» бегущей
    /// синусоидой с сильным свечением. Без ядра и расходящихся колец.
    func setProcessing() {
        phase = .processing
        processingPhase = 0
        bars.forEach { bar in
            bar.opacity = 1
            applyRecordingGradient(bar)
            applyGlow(bar, on: true)
        }
        startTimer()
        needsLayout = true   // обводку и сжатую раскладку волны строит layout()
    }

    func setStatus(color: NSColor) {
        phase = .status(color)
        stopTimer()
        removeProcessingRim()
        bars.forEach { bar in
            bar.opacity = 1
            bar.colors = [color.cgColor, color.cgColor]
            applyGlow(bar, on: false)
        }
        renderStaticStatus()
    }

    /// Неоновое свечение бара (режим обработки) — тот же бренд-градиент, что у обводки.
    private func applyGlow(_ bar: CAGradientLayer, on: Bool) {
        if on {
            bar.shadowColor = DS.Color.accentCyan.cgColor
            bar.shadowRadius = 2.5
            bar.shadowOpacity = 0.45
            bar.shadowOffset = .zero
        } else {
            bar.shadowOpacity = 0
        }
    }

    // MARK: Timer / tick

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !buffer.isEmpty else { return }
        switch phase {
        case .recording:
            guard !recordingIsIdle else {
                renderIdleDots(animated: true)
                return
            }
            // Симметричная «пляшущая» волна: каждый бар реагирует на текущий уровень
            // микрофона, в центре — выше, к краям — ниже, с независимым джиттером.
            let count = buffer.count
            for i in 0..<count {
                let t = CGFloat(i) / CGFloat(max(1, count - 1))   // 0…1
                let centerDist = abs(t - 0.5) * 2                  // 0 в центре, 1 на краях
                let envelope = 1 - centerDist * 0.65
                let jitter = 0.7 + 0.3 * CGFloat.random(in: 0...1)
                buffer[i] = currentLevel * envelope * jitter
            }
        case .processing:
            // Бегущая звуковая волна: высоко в центре, сходит к краям, «течёт» вбок.
            processingPhase += 0.30
            let count = buffer.count
            for i in 0..<count {
                let t = CGFloat(i) / CGFloat(max(1, count - 1))     // 0…1
                let envelope = sin(t * .pi)                          // 0 у краёв, 1 в центре
                let travel = 0.5 + 0.5 * sin(t * .pi * 4 - processingPhase)
                buffer[i] = 0.16 + 0.84 * envelope * travel
            }
        case .status:
            break
        }
        applyHeights(animated: true)
    }

    // MARK: Геометрия и отрисовка

    private func applyRecordingGradient(_ bar: CAGradientLayer) {
        bar.opacity = 1
        bar.colors = [DS.Color.accentViolet.cgColor, DS.Color.accentCyan.cgColor]
    }

    private func rebuildBars() {
        let pitch = barWidth + barGap
        let regionW = max(0, bounds.width - 2 * waveInsetX)
        let count = max(3, Int((regionW + barGap) / pitch))
        guard count != bars.count else { return }

        bars.forEach { $0.removeFromSuperlayer() }
        bars = (0..<count).map { _ in
            let l = CAGradientLayer()
            l.type = .axial
            // violet снизу → cyan сверху (CA coords: startPoint.y=0 = низ слоя)
            l.startPoint = CGPoint(x: 0.5, y: 0)
            l.endPoint = CGPoint(x: 0.5, y: 1)
            l.colors = [DS.Color.accentViolet.cgColor, DS.Color.accentCyan.cgColor]
            l.cornerRadius = barWidth / 2
            layer?.addSublayer(l)
            return l
        }
        heights = Array(repeating: minBar, count: count)
        buffer = (0..<count).map { i in
            let t = Double(i) / Double(max(1, count - 1))
            return CGFloat(0.08 + 0.10 * sin(t * .pi))
        }
    }

    private func applyHeights(animated: Bool) {
        guard bounds.width > 0, !bars.isEmpty else { return }
        let pitch = barWidth + barGap
        let totalWidth = CGFloat(bars.count) * pitch - barGap
        // Волна центрируется внутри зоны с отступом от краёв (в обработке — от обводки).
        let regionW = bounds.width - 2 * waveInsetX
        var x = waveInsetX + (regionW - totalWidth) / 2
        let maxBar = bounds.height - 2 * waveInsetY
        let cy = bounds.height / 2
        let count = bars.count

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(1.0 / 30.0) }
        for (i, bar) in bars.enumerated() {
            let d = min(i, count - 1 - i)
            let taper: CGFloat = d == 0 ? 0.5 : (d == 1 ? 0.78 : 1.0)
            let target = minBar + (maxBar - minBar) * min(1, buffer[i]) * taper
            heights[i] += (target - heights[i]) * 0.5
            let bh = max(minBar, heights[i])
            bar.frame = NSRect(x: x, y: cy - bh / 2, width: barWidth, height: bh)
            x += pitch
        }
        CATransaction.commit()
    }

    private func renderStaticStatus() {
        guard !bars.isEmpty else { return }
        let count = bars.count
        for i in 0..<count {
            let t = Double(i) / Double(max(1, count - 1))
            buffer[i] = CGFloat(0.18 + 0.42 * sin(t * .pi))
            heights[i] = minBar
        }
        for _ in 0..<6 { applyHeights(animated: false) }
    }

    private func renderIdleDots(animated: Bool) {
        guard !bars.isEmpty else { return }
        for i in buffer.indices { buffer[i] = idleLevel }
        for i in heights.indices { heights[i] = minBar }
        applyHeights(animated: animated)
    }

    // MARK: Светящаяся обводка (Siri-стиль): поток бренд-градиента по кромке капсулы

    /// Конический бренд-градиент, центрированный в `bounds` (вращается вокруг центра).
    private func makeConicGradient(colors: [CGColor], side: CGFloat) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.type = .conic
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 1.0, y: 0.5)
        g.colors = colors
        g.locations = [0, 0.27, 0.5, 0.73, 1] as [NSNumber]
        g.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        return g
    }

    /// Бесконечное вращение слоя вокруг центра — конический градиент «течёт» по кругу.
    private func spinAnimation(duration: CFTimeInterval, clockwise: Bool) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = 0
        a.toValue = (clockwise ? 1.0 : -1.0) * 2 * Double.pi
        a.duration = duration
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .linear)
        return a
    }

    /// Светящаяся обводка по кромке капсулы: вращающийся конический cyan↔violet под кольцом-маской
    /// + мягкое cyan-свечение. Кладётся ПОД бары, чтобы волна читалась поверх обводки.
    private func addProcessingRim() {
        removeProcessingRim()
        guard bounds.width > 1, bounds.height > 1 else { return }
        let cyan = DS.Color.accentCyan
        let violet = DS.Color.accentViolet
        let shine = DS.Color.accentCyan.blended(withFraction: 0.6, of: .white) ?? .white
        let side = max(bounds.width, bounds.height) * 1.8

        let rimHost = CALayer()
        rimHost.frame = bounds
        rimHost.masksToBounds = false
        let rimSpin = makeConicGradient(
            colors: [cyan.cgColor, violet.cgColor, shine.cgColor, violet.cgColor, cyan.cgColor],
            side: side)
        rimHost.addSublayer(rimSpin)

        let lw: CGFloat = 0.8   // тонкая обводка (Тико: 0.8–0.9 px)
        let r = bounds.height / 2 - lw / 2
        let ring = CAShapeLayer()
        ring.path = CGPath(roundedRect: bounds.insetBy(dx: lw / 2, dy: lw / 2),
                           cornerWidth: r, cornerHeight: r, transform: nil)
        ring.lineWidth = lw
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor.black.cgColor
        rimHost.mask = ring
        rimHost.shadowColor = cyan.cgColor
        rimHost.shadowRadius = 3
        rimHost.shadowOpacity = 0.32
        rimHost.shadowOffset = .zero
        rimSpin.add(spinAnimation(duration: 2.8, clockwise: true), forKey: "spin")

        if let first = bars.first {
            layer?.insertSublayer(rimHost, below: first)
        } else {
            layer?.addSublayer(rimHost)
        }
        processingRimLayers = [rimHost]
    }

    private func removeProcessingRim() {
        processingRimLayers.forEach { $0.removeFromSuperlayer() }
        processingRimLayers.removeAll()
    }

    override func layout() {
        super.layout()
        rebuildBars()
        // Бары перестроены под актуальные bounds — в обработке возвращаем свечение и обводку.
        if case .processing = phase {
            bars.forEach { applyGlow($0, on: true) }
            addProcessingRim()
        } else {
            removeProcessingRim()
        }
        if case .recording = phase, recordingIsIdle {
            renderIdleDots(animated: false)
        } else {
            applyHeights(animated: false)
        }
    }
}

// MARK: - CircleIconButton

@MainActor
private final class CircleIconButton: NSView {
    private let imageView = NSImageView()
    private let background: NSColor
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    init(symbolName: String, background: NSColor, foreground: NSColor,
         pointSize: CGFloat = 12, weight: NSFont.Weight = .bold) {
        self.background = background
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = background.cgColor

        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        imageView.contentTintColor = foreground
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        imageView.frame = bounds.insetBy(dx: bounds.width * 0.28, dy: bounds.height * 0.28)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = background.blended(withFraction: 0.18, of: .white)?.cgColor ?? background.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = background.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
