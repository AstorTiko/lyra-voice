import AppKit
import LyraVoiceCore

@MainActor
protocol OverlayControllerDelegate: AnyObject {
    func overlayDidAccept()
    func overlayDidCancel()
}

enum OverlayState: Equatable {
    case recording(seconds: Int, level: Double)
    case processing(modelName: String)
    case inserted
    case copied
    case error(String)
    /// Живая транскрипция: growing-window текст + контекст целевого приложения.
    case streaming(text: String, targetApp: String?, micName: String?)

    var title: String {
        switch self {
        case .recording, .streaming:
            return L.t("Слушаю", "Listening")
        case .processing:
            return L.t("Распознаю", "Transcribing")
        case .inserted:
            return L.t("Вставлено", "Pasted")
        case .copied:
            return L.t("Скопировано", "Copied")
        case .error:
            return L.t("Нужно внимание", "Needs attention")
        }
    }

    var subtitle: String {
        switch self {
        case let .recording(seconds, _):
            return L.t("Записано \(seconds) c", "Recorded \(seconds) s")
        case let .processing(modelName):
            return L.t("Распознаю моделью \(modelName)", "Transcribing with \(modelName)")
        case .inserted:
            return L.t("Текст вставлен", "Text pasted")
        case .copied:
            return L.t("В буфере — вставьте через ⌘V", "On the clipboard — paste with ⌘V")
        case let .error(message):
            return message
        case .streaming:
            return ""
        }
    }
}

@MainActor
final class OverlayController {
    weak var delegate: OverlayControllerDelegate? {
        didSet {
            contentView.delegate = self
        }
    }

    /// Режим показа — задаётся из настроек (push-to-talk / toggle) перед записью.
    var presentationMode: OverlayPresentationMode = .toggle
    /// Режим отображения оверлея из настроек пользователя.
    var displayMode: OverlayDisplayMode = .streaming

    private var window: NSPanel?
    private let contentView = OverlayView(frame: NSRect(
        x: 0,
        y: 0,
        width: CGFloat(OverlayMetrics.toggleSize.width),
        height: CGFloat(OverlayMetrics.toggleSize.height)
    ))

    private var pillSize: OverlaySize {
        presentationMode == .pushToTalk ? OverlayMetrics.pushToTalkSize : OverlayMetrics.toggleSize
    }

    func show(state: OverlayState) {
        // Режим .none: оверлей скрыт полностью.
        guard displayMode != .none else { return }

        // Режим .pill: streaming-панель не показываем.
        if displayMode == .pill, case .streaming = state { return }

        let panel = window ?? makeWindow()
        contentView.setMode(presentationMode)
        let isStreaming: Bool
        if case .streaming = state, displayMode == .streaming {
            isStreaming = true
        } else {
            isStreaming = false
        }
        // Центрируем ДО resize: тогда анимация роста (compact → панель) идёт ровно
        // по центру снизу, а не из угла (0,0) свежесозданного окна с последующим рывком.
        placeNearBottom(panel)
        resize(panel, streaming: isStreaming)
        contentView.render(state: state)
        panel.orderFrontRegardless()
        window = panel
    }

    /// Частое (≈12×/сек) обновление уровня аудиоволны БЕЗ resize/reposition/reorder окна.
    /// Это убирает рывки: тяжёлые операции с окном выполняются только в `show(state:)`.
    /// Если показана streaming-панель (волна скрыта) — метод ничего не делает.
    func updateRecordingLevel(_ level: Double) {
        guard displayMode != .none, let window, window.isVisible else { return }
        contentView.updateWaveformLevel(level)
    }

    private func resize(_ panel: NSPanel, streaming: Bool) {
        let size = streaming ? OverlayMetrics.streamingSize : pillSize
        let newW = CGFloat(size.width)
        let newH = CGFloat(size.height)
        let current = panel.frame

        // Размер уже верный (частый случай: каждый чанк стриминга зовёт show()) —
        // не дёргаем окно, только просим перелэйаут контента под новый текст.
        if abs(current.width - newW) < 0.5 && abs(current.height - newH) < 0.5 {
            contentView.needsLayout = true
            return
        }

        // Центрируем по горизонтали относительно текущего положения панели.
        let frame = NSRect(x: current.midX - newW / 2, y: current.minY, width: newW, height: newH)
        // A.3: рост из компактного pill в стриминг-панель — плавно. Сжатие обратно
        // (стоп → processing) делаем мгновенно, чтобы панель не «складывалась» на глазах.
        let growing = newW > current.width + 0.5
        if growing {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.24
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: false)
        }
        // contentView с autoresizingMask следует за окном — лэйаут пересчитается сам.
        contentView.needsLayout = true
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: CGFloat(OverlayMetrics.size.width),
                height: CGFloat(OverlayMetrics.size.height)
            ),
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
        panel.ignoresMouseEvents = false
        panel.contentView = contentView
        // Контент следует за окном при анимированном ресайзе (A.3 compact→grow).
        contentView.autoresizingMask = [.width, .height]
        return panel
    }

    private func placeNearBottom(_ panel: NSPanel) {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.minY + CGFloat(OverlayMetrics.bottomOffset)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

extension OverlayController: OverlayViewDelegate {
    func overlayViewDidAccept() {
        delegate?.overlayDidAccept()
    }

    func overlayViewDidCancel() {
        delegate?.overlayDidCancel()
    }
}
