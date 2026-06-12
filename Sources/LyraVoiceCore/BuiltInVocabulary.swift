import Foundation

public enum VocabularyCategory: String, Codable, Equatable, Sendable {
    case aiTool
    case brand
    case project
    case place
}

public struct VocabularyEntry: Codable, Equatable, Sendable {
    public var phrases: [String]
    public var canonical: String
    public var category: VocabularyCategory

    public init(phrases: [String], canonical: String, category: VocabularyCategory) {
        self.phrases = phrases
        self.canonical = canonical
        self.category = category
    }
}

public enum BuiltInVocabulary {
    public static let entries: [VocabularyEntry] = [
        VocabularyEntry(
            phrases: ["клод", "claude"],
            canonical: "Claude",
            category: .aiTool
        ),
        VocabularyEntry(
            phrases: ["клод код", "клод коде", "клод козе", "claude code"],
            canonical: "Claude Code",
            category: .aiTool
        ),
        VocabularyEntry(
            phrases: ["кодекс", "codex"],
            canonical: "Codex",
            category: .aiTool
        ),
        VocabularyEntry(
            phrases: ["клауд", "клоуд", "cloud"],
            canonical: "Cloud",
            category: .brand
        ),
        VocabularyEntry(
            phrases: ["айклауд", "ай клауд", "ай клоуд", "icloud", "i cloud"],
            canonical: "iCloud",
            category: .brand
        ),
        VocabularyEntry(
            phrases: ["чат джипити", "чат gpt", "chat gpt", "чатгпт"],
            canonical: "ChatGPT",
            category: .aiTool
        ),
        VocabularyEntry(
            phrases: ["джипити", "gpt"],
            canonical: "GPT",
            category: .aiTool
        ),
        VocabularyEntry(
            phrases: ["опен эй ай", "open ai", "openai"],
            canonical: "OpenAI",
            category: .brand
        ),
        VocabularyEntry(
            phrases: ["антропик", "anthropic"],
            canonical: "Anthropic",
            category: .brand
        ),
        VocabularyEntry(
            phrases: ["перплексити", "perplexity"],
            canonical: "Perplexity",
            category: .aiTool
        ),
        // NB: НЕ маппим русское «курсор» → «Cursor» — это обычное слово (текстовый курсор),
        // подмена на название IDE искажает смысл («курсор на инпуте» ≠ «Cursor на инпуте»).
        // Английское написание «cursor» оставляем — оно явно указывает на IDE.
        VocabularyEntry(
            phrases: ["cursor"],
            canonical: "Cursor",
            category: .aiTool
        ),
        VocabularyEntry(
            phrases: ["рейкаст", "raycast"],
            canonical: "Raycast",
            category: .brand
        ),
        VocabularyEntry(
            phrases: ["фигма", "figma"],
            canonical: "Figma",
            category: .brand
        ),
        VocabularyEntry(
            phrases: ["лира войс", "lyra voice"],
            canonical: "Lyra Voice",
            category: .project
        ),
        VocabularyEntry(
            phrases: ["нью йорк", "new york"],
            canonical: "Нью-Йорк",
            category: .place
        ),
        VocabularyEntry(
            phrases: ["сан франциско", "san francisco"],
            canonical: "San Francisco",
            category: .place
        )
    ]
}
