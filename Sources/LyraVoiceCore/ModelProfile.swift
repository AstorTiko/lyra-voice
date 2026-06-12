import Foundation

public struct ModelProfile: Equatable, Sendable {
    public enum Priority: String, Sendable {
        case speed
        case balanced
        case accuracy
    }

    public let id: String
    public let displayName: String
    public let fileName: String
    public let downloadURL: URL
    public let priority: Priority
    public let sizeLabel: String
    public let speedScore: Int
    public let accuracyScore: Int
    public let description: String

    public init(
        id: String,
        displayName: String,
        fileName: String,
        downloadURL: URL,
        priority: Priority,
        sizeLabel: String,
        speedScore: Int,
        accuracyScore: Int,
        description: String
    ) {
        self.id = id
        self.displayName = displayName
        self.fileName = fileName
        self.downloadURL = downloadURL
        self.priority = priority
        self.sizeLabel = sizeLabel
        self.speedScore = speedScore
        self.accuracyScore = accuracyScore
        self.description = description
    }

    public var readyMessage: String {
        L.t("\(displayName) готова. \(comparisonSummary)", "\(displayName) is ready. \(comparisonSummary)")
    }

    public var missingMessage: String {
        L.t("\(displayName) ещё не скачана. Скачайте \(sizeLabel), чтобы начать диктовку.",
            "\(displayName) isn't downloaded yet. Download \(sizeLabel) to start dictating.")
    }

    public var comparisonSummary: String {
        L.t("Скорость \(speedScore)/10, точность \(accuracyScore)/10. \(description)",
            "Speed \(speedScore)/10, accuracy \(accuracyScore)/10. \(description)")
    }

    public var menuTitle: String {
        L.t("\(displayName) - скорость \(speedScore)/10 - точность \(accuracyScore)/10",
            "\(displayName) - speed \(speedScore)/10 - accuracy \(accuracyScore)/10")
    }

    public static let builtInProfiles: [ModelProfile] = [
        ModelProfile(
            id: "tiny",
            displayName: "Tiny",
            fileName: "ggml-tiny.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!,
            priority: .speed,
            sizeLabel: "43.5 MB",
            speedScore: 10,
            accuracyScore: 2,
            description: L.t("Самая быстрая модель для тестов и слабых Mac; русскую речь понимает грубее, пунктуация часто требует правки.",
                             "Fastest model for testing and weaker Macs; rougher on speech, punctuation often needs fixing.")
        ),
        ModelProfile(
            id: "small",
            displayName: "Small",
            fileName: "ggml-small.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
            priority: .balanced,
            sizeLabel: "264 MB",
            speedScore: 8,
            accuracyScore: 6,
            description: L.t("Лёгкий повседневный вариант, когда важна скорость и приемлемая чистота текста без долгой обработки.",
                             "Light everyday option when speed matters and decent text quality is enough without long processing.")
        ),
        ModelProfile(
            id: "medium",
            displayName: "Medium",
            fileName: "ggml-medium.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
            priority: .balanced,
            sizeLabel: "823 MB",
            speedScore: 6,
            accuracyScore: 8,
            description: L.t("Сбалансированный выбор для длинной русской диктовки: заметно чище Tiny/Small, но без максимальной задержки.",
                             "Balanced choice for longer dictation: noticeably cleaner than Tiny/Small, without the heaviest latency.")
        ),
        ModelProfile(
            id: "turbo",
            displayName: "Turbo",
            fileName: "ggml-large-v3-turbo.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
            priority: .speed,
            sizeLabel: "1.62 GB",
            speedScore: 8,
            accuracyScore: 8,
            description: L.t("Быстрый вариант Large v3. Обычно лучший дефолт: хорошая русская речь, нормальная пунктуация и умеренная задержка.",
                             "Fast Large v3 variant. Usually the best default: good speech, decent punctuation and moderate latency.")
        ),
        ModelProfile(
            id: "large-v3",
            displayName: "Large v3",
            fileName: "ggml-large-v3.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
            priority: .accuracy,
            sizeLabel: "3.1 GB",
            speedScore: 3,
            accuracyScore: 10,
            description: L.t("Самая точная локальная модель для русской диктовки: лучше держит смысл, пунктуацию и сложные формулировки, но работает медленнее.",
                             "Most accurate local model: best at meaning, punctuation and complex phrasing, but slower.")
        )
    ]

    public static func profile(id: String) -> ModelProfile? {
        builtInProfiles.first { $0.id == id }
    }
}
