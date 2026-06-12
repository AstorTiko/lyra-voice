import Foundation

public enum ControlPanelState: Equatable, Sendable {
    case idle
    case recording(seconds: Int)
    case processing(modelName: String)
    case inserted
    case copied
    case error(String)

    public var statusTitle: String {
        switch self {
        case .idle:
            return L.t("Готово", "Ready")
        case .recording:
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

    public var statusDetail: String {
        switch self {
        case .idle:
            return L.t("Начните запись или запустите тестовое аудио", "Start recording or run the test audio")
        case let .recording(seconds):
            return L.t("Записано \(seconds) c", "Recorded \(seconds) s")
        case let .processing(modelName):
            return L.t("Распознаю моделью \(modelName)", "Transcribing with \(modelName)")
        case .inserted:
            return L.t("Текст вставлен в активное поле", "Text pasted into the active field")
        case .copied:
            return L.t("Текст в буфере. Вставьте через ⌘V (или включите авто-вставку)", "Text is on the clipboard. Paste with ⌘V (or enable auto-paste)")
        case let .error(message):
            return message
        }
    }

    public var canStartRecording: Bool {
        switch self {
        case .recording, .processing:
            return false
        case .idle, .inserted, .copied, .error:
            return true
        }
    }

    public var canStopRecording: Bool {
        switch self {
        case .recording:
            return true
        case .idle, .processing, .inserted, .copied, .error:
            return false
        }
    }

    public var canCancelRecording: Bool {
        switch self {
        case .recording:
            return true
        case .idle, .processing, .inserted, .copied, .error:
            return false
        }
    }

    public var canRunTestAudio: Bool {
        switch self {
        case .idle, .inserted, .copied, .error:
            return true
        case .recording, .processing:
            return false
        }
    }
}
