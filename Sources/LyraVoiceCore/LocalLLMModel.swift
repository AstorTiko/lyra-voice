import Foundation

/// Модель локальной LLM-полировки (GGUF для llama.cpp). Хранится рядом с
/// whisper-моделями в `modelDirectoryPath`. Пока — один дефолт; список можно
/// расширить (например, более лёгкая 1.5B для скорости).
public struct LocalLLMModel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let fileName: String
    public let downloadURL: URL
    public let sizeLabel: String
    public let description: String

    public init(
        id: String,
        displayName: String,
        fileName: String,
        downloadURL: URL,
        sizeLabel: String,
        description: String
    ) {
        self.id = id
        self.displayName = displayName
        self.fileName = fileName
        self.downloadURL = downloadURL
        self.sizeLabel = sizeLabel
        self.description = description
    }

    /// Дефолтная модель полировки: Qwen2.5-3B-Instruct (Q4_K_M) — баланс
    /// качество/скорость/память для редактирования русского текста на Apple Silicon.
    public static let qwen3BInstruct = LocalLLMModel(
        id: "qwen2.5-3b-instruct-q4",
        displayName: "Qwen2.5 3B Instruct",
        fileName: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
        downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf")!,
        sizeLabel: "1.93 GB",
        description: "Локальная модель «Красиво»: чистит грамматику, пунктуацию и абзацы офлайн, без отправки текста в облако."
    )

    public static let `default` = qwen3BInstruct

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
