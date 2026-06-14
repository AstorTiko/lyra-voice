import Foundation

/// Полировка распознанного текста. Реализации: правила (rules), локальная LLM (MLX),
/// облачная LLM. Уровень выбирается пользователем в настройках.
/// Вход — текст после базовой очистки транскрайбера, выход — готовый к вставке.
public protocol TextPolisher: Sendable {
    func polish(_ text: String) async throws -> String
}

/// Правила: команды пунктуации + чистка паразитов + словарь + капитализация.
/// Мгновенно, офлайн, бесплатно. Всегда доступна как база.
public struct RulePolisher: TextPolisher {
    private let replacements: [(from: String, to: String)]
    private let applyVoiceCommands: Bool
    private let removeFillers: Bool
    private let context: AppContextProfile

    public init(
        dictionary: [DictionaryEntry] = [],
        applyVoiceCommands: Bool = true,
        removeFillers: Bool = true,
        context: AppContextProfile = AppContextProfile()
    ) {
        self.replacements = dictionary.map { ($0.from, $0.to) }
        self.applyVoiceCommands = applyVoiceCommands
        self.removeFillers = removeFillers
        self.context = context
    }

    public func polish(_ text: String) async throws -> String {
        var result = text
        if context.format == .password {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if context.format == .url {
            return TextPostProcessor.urlLiteralCleanup(result)
        }
        if context.format == .searchQuery {
            return TextPostProcessor.searchQueryCleanup(result)
        }
        if context.format == .filePath {
            return TextPostProcessor.filePathLiteralCleanup(result)
        }

        if context.format == .terminalCommand || context.format == .code {
            result = TextPostProcessor.applyVocabulary(result, userPairs: replacements)
            return TextPostProcessor.codeLikeCleanup(result)
        }

        if applyVoiceCommands {
            result = TextPostProcessor.applyCorrectionCommands(result)
            result = TextPostProcessor.applyVoiceCommands(result)
        }
        if removeFillers {
            result = TextPostProcessor.removeFillerWords(result)
        }
        result = TextPostProcessor.applyVocabulary(result, userPairs: replacements)
        result = TextPostProcessor.applyContextProperNouns(result, context: context.screenContext)
        result = TextPostProcessor.normalizeDatesAndMoney(result)
        result = TextPostProcessor.formatExplicitLists(result)
        result = TextPostProcessor.insertIntroductoryCommas(result)
        result = TextPostProcessor.lightCleanup(result)
        result = TextPostProcessor.capitalizeSentences(result)
        if context.format == .email {
            return TextPostProcessor.emailCleanup(result)
        }
        if context.format == .chatMessage {
            result = TextPostProcessor.chatCleanup(result)
        }
        // Разбиваем длинную диктовку на абзацы по смыслу — иначе текст идёт
        // сплошняком. Уважает явные «новый абзац» (не трогает, если \n\n уже есть).
        if TextPostProcessor.containsStructuredList(result) {
            return result
        }
        result = TextPostProcessor.dictationCleanup(result)
        if context.format == .documentText,
           let last = result.trimmingCharacters(in: .whitespacesAndNewlines).last,
           !".!?\n".contains(last) {
            result += "."
        }
        return TextPostProcessor.applyContextualInsertion(result, context: context.screenContext)
    }
}

/// Фабрика полировщиков по выбранному уровню.
/// Пока localLLM и cloud не реализованы — безопасный фолбэк на правила
/// (текст всё равно причёсывается, просто без LLM-магии).
public enum TextPolisherFactory {
    /// - localLLMEndpoint: адрес локального `llama-server` (`/v1/chat/completions`).
    ///   Если уровень `.localLLM`, но сервер недоступен (nil) — безопасно падаем на правила.
    public static func make(
        level: PolishLevel,
        dictionary: [DictionaryEntry],
        removeFillers: Bool = true,
        localLLMEndpoint: URL? = nil,
        context: AppContextProfile = AppContextProfile(),
        log: (@Sendable (String) -> Void)? = nil
    ) -> TextPolisher {
        let rules = RulePolisher(
            dictionary: dictionary,
            removeFillers: removeFillers,
            context: context
        )
        switch level {
        case .rules:
            return rules
        case .localLLM:
            guard let endpoint = localLLMEndpoint else {
                log?("LLM polish: endpoint nil (сервер не запущен) → только правила")
                return rules
            }
            let systemPrompt = context.format == .aiPrompt
                ? TextCleanupPrompt.promptify()
                : TextCleanupPrompt.system()
            return LocalLLMPolisher(
                endpoint: endpoint,
                systemPrompt: systemPrompt,
                fallback: rules,
                dictionary: dictionary,
                context: context,
                removeFillers: removeFillers,
                log: log
            )
        case .cloud:
            // TODO: облачная LLM по API-ключу с системным промптом
            // `TextCleanupPrompt.system()`. Пока — правила.
            return rules
        }
    }
}
