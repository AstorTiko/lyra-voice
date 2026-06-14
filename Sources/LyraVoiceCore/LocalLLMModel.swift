import Foundation

/// Модель локальной LLM-полировки (GGUF для llama.cpp). Хранится рядом с
/// whisper-моделями в `modelDirectoryPath`. Каталог из нескольких вариантов одного
/// семейства Qwen2.5-Instruct — пользователь выбирает баланс скорость/качество.
///
/// Почему именно Qwen2.5-Instruct (а не reasoning-модели вроде Qwen3/T-pro): задача —
/// «отредактируй и верни ТОЛЬКО текст», без размышлений. Instruct-модели Qwen2.5 надёжно
/// следуют этой инструкции, не генерируют reasoning-трейсы, а наш системный промпт и
/// постобработка (`<|im_end|>`-токены и т.п.) уже заточены под их чат-шаблон — апгрейд
/// размера не требует менять логику полировки.
public struct LocalLLMModel: Equatable, Sendable {
    public enum Tier: String, Sendable {
        case fast       // 3B — быстрее всего, базовое качество
        case balanced   // 7B — рекомендованный баланс
        case quality    // 14B — максимум качества для русского, заметно медленнее
    }

    public let id: String
    public let displayName: String
    public let fileName: String
    public let downloadURL: URL
    public let sizeLabel: String
    public let tier: Tier
    public let speedScore: Int
    public let qualityScore: Int
    public let description: String

    public init(
        id: String,
        displayName: String,
        fileName: String,
        downloadURL: URL,
        sizeLabel: String,
        tier: Tier,
        speedScore: Int,
        qualityScore: Int,
        description: String
    ) {
        self.id = id
        self.displayName = displayName
        self.fileName = fileName
        self.downloadURL = downloadURL
        self.sizeLabel = sizeLabel
        self.tier = tier
        self.speedScore = speedScore
        self.qualityScore = qualityScore
        self.description = description
    }

    // MARK: - Каталог (Qwen2.5-Instruct, Q4_K_M GGUF от bartowski)

    /// 3B — быстрая база. Уже использовалась как единственный дефолт, оставлена для
    /// совместимости (у текущих пользователей она скачана).
    public static let qwen3BInstruct = LocalLLMModel(
        id: "qwen2.5-3b-instruct-q4",
        displayName: "Qwen2.5 3B",
        fileName: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
        downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf")!,
        sizeLabel: "1.93 GB",
        tier: .fast,
        speedScore: 9,
        qualityScore: 5,
        description: L.t("Быстрая: полировка почти мгновенная, базовая грамматика. Для слабых Mac и когда скорость важнее.",
                         "Fast: near-instant polish, basic grammar. For weaker Macs and when speed matters most.")
    )

    /// 7B — рекомендованный баланс качества и скорости для повседневной диктовки.
    public static let qwen7BInstruct = LocalLLMModel(
        id: "qwen2.5-7b-instruct-q4",
        displayName: "Qwen2.5 7B",
        fileName: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
        downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf")!,
        sizeLabel: "4.68 GB",
        tier: .balanced,
        speedScore: 7,
        qualityScore: 7,
        description: L.t("Рекомендуется: заметно грамотнее 3B (окончания, смысл, пунктуация), полировка за пару секунд.",
                         "Recommended: noticeably better than 3B (agreement, meaning, punctuation), polish in a couple seconds.")
    )

    /// 14B — максимум качества русской полировки. Тяжелее и медленнее; нужен Mac с ≥16–32 ГБ.
    public static let qwen14BInstruct = LocalLLMModel(
        id: "qwen2.5-14b-instruct-q4",
        displayName: "Qwen2.5 14B",
        fileName: "Qwen2.5-14B-Instruct-Q4_K_M.gguf",
        downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF/resolve/main/Qwen2.5-14B-Instruct-Q4_K_M.gguf")!,
        sizeLabel: "8.99 GB",
        tier: .quality,
        speedScore: 4,
        qualityScore: 9,
        description: L.t("Максимальное качество: лучше всех держит смысл и стиль на длинной речи. Медленнее, нужен запас памяти.",
                         "Top quality: best at keeping meaning and style on long speech. Slower, needs spare RAM.")
    )

    public static let builtInModels: [LocalLLMModel] = [qwen3BInstruct, qwen7BInstruct, qwen14BInstruct]

    /// Дефолт остаётся 3B для обратной совместимости (она уже скачана у текущих
    /// пользователей) — переход на 7B/14B пользователь делает явно, скачав модель.
    public static let `default` = qwen3BInstruct

    /// Рекомендованная модель для подсказки в UI.
    public static let recommended = qwen7BInstruct

    public static func find(id: String) -> LocalLLMModel? {
        builtInModels.first { $0.id == id }
    }

    /// Короткая подпись уровня для UI-селектора.
    public var tierTitle: String {
        switch tier {
        case .fast: return L.t("быстрая", "fast")
        case .balanced: return L.t("баланс", "balanced")
        case .quality: return L.t("точность", "quality")
        }
    }

    // MARK: - Файл модели

    /// Полный путь к файлу модели в каталоге моделей.
    public func fileURL(inModelDirectory directory: String) -> URL {
        URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(fileName)
    }

    /// Скачана ли модель (файл существует и непустой).
    public func isDownloaded(inModelDirectory directory: String) -> Bool {
        let url = fileURL(inModelDirectory: directory)
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }
}
