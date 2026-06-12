import Foundation

public enum TextPostProcessor {
    public static func lightCleanup(_ input: String) -> String {
        removeKnownHallucinations(input)
            // Служебные теги whisper в квадратных скобках: [BLANK_AUDIO], [_BEG_] и т.п.
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #" +([,.!?;:])"#, with: "$1", options: .regularExpression)
            // «открыть/закрыть кавычки» оставляют пробел внутри кавычек («слово» не «слово »).
            .replacingOccurrences(of: #"«\s+"#, with: "«", options: .regularExpression)
            .replacingOccurrences(of: #"\s+»"#, with: "»", options: .regularExpression)
            .replacingOccurrences(of: #"([.!?])\1+"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #",\s*,"#, with: ",", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func codeLikeCleanup(_ input: String) -> String {
        removeKnownHallucinations(input)
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func emailCleanup(_ input: String) -> String {
        let cleaned = lightCleanup(input)
        var lines = cleaned
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return cleaned }
        splitTrailingEmailSignoff(&lines)

        lines[0] = formatEmailGreeting(lines[0])
        if let last = lines.indices.last {
            lines[last] = formatEmailSignoff(lines[last])
        }

        return lines.joined(separator: "\n\n")
    }

    /// Разбивает длинную диктовку на абзацы ПО СМЫСЛУ, а не механически по числу
    /// предложений. Принципы:
    /// - короткие диктовки (≤3 предложений) не дробим вовсе — абзац «просто так» мешает;
    /// - разрыв ставим на явном маркере смыслового перехода и только если в текущем
    ///   абзаце уже есть мысль (≥2 предложения), чтобы не плодить осколки;
    /// - страховка от «простыни»: очень длинный абзац без маркеров всё же рвём, но
    ///   мягко (высокий порог) и без одиноких предложений-хвостов.
    /// Если пользователь уже расставил абзацы («новый абзац» → \n\n) — не трогаем.
    public static func dictationCleanup(_ input: String, softMaxSentencesPerParagraph: Int = 8) -> String {
        let cleaned = lightCleanup(input)
        guard !cleaned.contains("\n\n") else { return cleaned }

        let sentences = dropConsecutiveDuplicates(splitSentences(cleaned))
        guard sentences.count > 3 else {
            return sentences.joined(separator: " ")
        }
        let paragraphs = groupSentencesIntoSemanticParagraphs(sentences, softMax: softMaxSentencesPerParagraph)
        return paragraphs.map { $0.joined(separator: " ") }.joined(separator: "\n\n")
    }

    // MARK: - Голосовые команды форматирования

    /// Превращает произнесённые команды в реальную пунктуацию/переносы.
    /// Работает поверх авто-пунктуации: если пользователь сказал «новый абзац» —
    /// добавляется разрыв. Команды распознаются как отдельные слова (\b, Unicode-aware).
    /// Порядок — от длинных фраз к коротким, чтобы «точка с запятой» не съелась «точкой».
    public static func applyVoiceCommands(_ input: String) -> String {
        let commands: [(pattern: String, replacement: String)] = [
            ("новый абзац", "\n\n"),
            ("новый параграф", "\n\n"),
            ("с новой строки", "\n"),
            ("новая строка", "\n"),
            ("перенос строки", "\n"),
            ("точка с запятой", ";"),
            ("вопросительный знак", "?"),
            ("восклицательный знак", "!"),
            ("двоеточие", ":"),
            ("открыть скобку", "("),
            ("закрыть скобку", ")"),
            ("открыть кавычки", "«"),
            ("закрыть кавычки", "»"),
            ("запятая", ","),
            ("двоеточие", ":"),
            ("длинное тире", " — "),
            ("короткое тире", " – "),
            ("тире", " — "),
            ("дефис", "-"),
            ("многоточие", "…"),
            ("точка", ".")
        ]
        var text = input
        for command in commands {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: command.pattern))\\b"
            text = text.replacingOccurrences(of: pattern, with: command.replacement, options: .regularExpression)
        }
        return text
    }

    // MARK: - Самопоправки (явные команды)

    /// Явные голосовые команды отмены/самопоправки: «зачеркни последнее слово»,
    /// «сотри последнее предложение», «отставить» и т.п. Удаляют предшествующий
    /// фрагмент и саму команду. НЕ пытаемся угадывать неявные самопоправки
    /// («встретимся в среду, нет, в четверг») — это семантическая задача без
    /// надёжного rule-based решения, ей занимается LLM-полировка («Красиво», A4).
    public static func applyCorrectionCommands(_ input: String) -> String {
        var text = input
        let sentenceCommands = [
            "зачеркни последнее предложение", "зачеркни предыдущее предложение",
            "сотри последнее предложение", "удали последнее предложение",
            "вычеркни последнее предложение",
            "отставить", "забудь это", "забудь последнее", "это не считово", "это не считается"
        ]
        let wordCommands = [
            "зачеркни последнее слово", "сотри последнее слово",
            "удали последнее слово", "вычеркни последнее слово",
            "зачеркни", "сотри", "удали", "вычеркни"
        ]
        for command in sentenceCommands {
            text = removeBeforeCommand(text, command: command, unit: .sentence)
        }
        for command in wordCommands {
            text = removeBeforeCommand(text, command: command, unit: .word)
        }
        return text
    }

    private enum CorrectionUnit { case word, sentence }

    /// Находит `command` (без учёта регистра, по границе слова) и удаляет вместе с ним
    /// предшествующий фрагмент: одно слово или одно предложение (до предыдущего `.!?`).
    /// Повторяет, пока команда встречается (например, две подряд «зачеркни»).
    private static func removeBeforeCommand(_ input: String, command: String, unit: CorrectionUnit) -> String {
        let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: command) + "\\b[.,!?…]*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        var text = input
        var safetyCounter = 0
        while safetyCounter < 10,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            safetyCounter += 1
            guard let matchRange = Range(match.range, in: text) else { break }
            let prefix = unit == .word
                ? removeTrailingWord(String(text[text.startIndex..<matchRange.lowerBound]))
                : removeTrailingSentence(String(text[text.startIndex..<matchRange.lowerBound]))
            let suffix = String(text[matchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            text = suffix.isEmpty ? prefix : (prefix.isEmpty ? suffix : "\(prefix) \(suffix)")
        }
        return text
    }

    /// Удаляет последнее слово (и хвостовую пунктуацию перед ним) из фрагмента.
    private static func removeTrailingWord(_ input: String) -> String {
        var text = input.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n,.!?;:—–-"))
        guard let lastSpace = text.range(of: #"\s"#, options: [.regularExpression, .backwards]) else {
            return ""
        }
        text = String(text[text.startIndex..<lastSpace.lowerBound])
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n,.!?;:—–-"))
    }

    /// Удаляет последнее предложение из фрагмента (до предыдущего `.!?`, включительно).
    private static func removeTrailingSentence(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n,.!?;:…"))
        guard let lastEnd = trimmed.range(of: #"[.!?][\s]*"#, options: [.regularExpression, .backwards]) else {
            return ""
        }
        return String(trimmed[trimmed.startIndex..<lastEnd.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Слова-паразиты

    /// Убирает речевые паразиты и звуки-заминки. Консервативный набор, чтобы не портить
    /// смысл: явные заминки удаляем всегда, дискурсивные паразиты — умеренный список.
    public static func removeFillerWords(_ input: String) -> String {
        // Звуки-заминки: ээ, эээ, мм, ммм, эм, хм, кхм. Узкий паттерн — НЕ трогает реальные
        // слова («мама», «а», «и»): требуем удвоение буквы или фиксированные сочетания.
        var text = input.replacingOccurrences(
            of: #"(?i)\b(?:[эа]{2,}|м{2,}|эм+|кхм|гм|хм|э-э|м-м|а-а)\b"#,
            with: "",
            options: .regularExpression
        )
        // Только однозначные вербальные тики. Сознательно НЕ удаляем «ну», «вот», «значит»,
        // «вообще», «в общем», «типа», «короче», «понимаешь», «слушай» — они часто несут смысл
        // (или вообще глаголы), и их удаление коверкает текст. Длинные фразы — первыми.
        let fillers = [
            "то есть как бы", "ну как бы", "так сказать", "это самое", "собственно говоря",
            "грубо говоря", "что называется", "как говорится", "если можно так сказать"
        ]
        for filler in fillers {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: filler))\\b"
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return text
    }

    // MARK: - Словарь замен

    /// Применяет пользовательский словарь: «джипити» → «GPT» и т.п.
    /// Сопоставление по слову, без учёта регистра.
    public static func applyReplacements(_ input: String, _ pairs: [(from: String, to: String)]) -> String {
        var text = input
        for pair in pairs where !pair.from.trimmingCharacters(in: .whitespaces).isEmpty {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: pair.from))\\b"
            text = text.replacingOccurrences(of: pattern, with: pair.to, options: .regularExpression)
        }
        return text
    }

    /// Применяет встроенный релизный словарь терминов, затем пользовательский словарь.
    /// Если пользователь добавил замену для той же произносимой фразы, встроенная
    /// замена отключается именно для этой фразы — пользовательский выбор важнее.
    public static func applyVocabulary(_ input: String, userPairs: [(from: String, to: String)]) -> String {
        let overridden = Set(userPairs.map { normalizedVocabularyKey($0.from) })
        var builtInPairs: [(from: String, to: String)] = []
        for entry in BuiltInVocabulary.entries {
            for phrase in entry.phrases where !overridden.contains(normalizedVocabularyKey(phrase)) {
                builtInPairs.append((from: phrase, to: entry.canonical))
            }
        }
        builtInPairs.sort { lhs, rhs in
            lhs.from.count == rhs.from.count ? lhs.from < rhs.from : lhs.from.count > rhs.from.count
        }
        var sortedUserPairs = userPairs
        sortedUserPairs.sort { lhs, rhs in
            lhs.from.count == rhs.from.count ? lhs.from < rhs.from : lhs.from.count > rhs.from.count
        }
        return applyReplacements(applyReplacements(input, builtInPairs), sortedUserPairs)
    }

    public static func normalizeDatesAndMoney(_ input: String) -> String {
        normalizeDollarAmounts(normalizeRussianDates(input))
    }

    public static func formatExplicitLists(_ input: String) -> String {
        formatNumberedList(input)
    }

    public static func containsStructuredList(_ input: String) -> Bool {
        input.range(of: #"(?m)^\d+\.\s+\S"#, options: .regularExpression) != nil
    }

    public static func urlLiteralCleanup(_ input: String) -> String {
        var text = input.lowercased()
        let replacements = [
            ("двоеточие", ":"), ("colon", ":"),
            ("слеш", "/"), ("slash", "/"),
            ("точка", "."), ("dot", "."),
            ("дефис", "-"), ("hyphen", "-"), ("dash", "-"),
            ("нижнее подчеркивание", "_"), ("underscore", "_"),
            ("вопросительный знак", "?"), ("question mark", "?"),
            ("амперсанд", "&"), ("ampersand", "&"),
            ("равно", "="), ("equals", "=")
        ]
        for replacement in replacements {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: replacement.0))\\b"
            text = text.replacingOccurrences(of: pattern, with: replacement.1, options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"\s*([:/._?=&%#-])\s*"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?\n\t"))
    }

    public static func filePathLiteralCleanup(_ input: String) -> String {
        var text = input
        let replacements = [
            ("слеш", "/"), ("slash", "/"),
            ("обратный слеш", "\\"), ("backslash", "\\"),
            ("точка", "."), ("dot", "."),
            ("дефис", "-"), ("hyphen", "-"),
            ("нижнее подчеркивание", "_"), ("underscore", "_")
        ]
        for replacement in replacements {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: replacement.0))\\b"
            text = text.replacingOccurrences(of: pattern, with: replacement.1, options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"\s*([/\\._-])\s*"#, with: "$1", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func searchQueryCleanup(_ input: String) -> String {
        let cleaned = lightCleanup(applyVoiceCommands(input))
        return stripTrailingSentencePeriod(cleaned).lowercasingFirstLetter()
    }

    public static func chatCleanup(_ input: String) -> String {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = cleaned.split { $0.isWhitespace || $0.isNewline }
        let sentenceMarks = cleaned.filter { ".!?".contains($0) }.count
        if words.count <= 8, sentenceMarks <= 1 {
            return stripTrailingSentencePeriod(cleaned).lowercasingFirstLetter()
        }
        return cleaned
    }

    public static func applyContextProperNouns(_ input: String, context: ScreenContextSnapshot?) -> String {
        let candidates = properNounCandidates(from: context)
        guard !candidates.isEmpty else { return input }

        var result = input
        for candidate in candidates.sorted(by: { $0.count > $1.count }) {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: candidate))\\b"
            result = result.replacingOccurrences(of: pattern, with: candidate, options: .regularExpression)
        }
        return result
    }

    /// Извлекает кандидатов в имена собственные/термины из текста экрана (заголовки,
    /// выделение, текст вокруг курсора): CamelCase- и многословные капитализированные
    /// фразы — обычно бренды/названия продуктов/проектов, а не начало предложения.
    /// Используется и для подстановки точного написания (`applyContextProperNouns`),
    /// и для краткого глоссария в LLM-промпт (`LocalLLMPolisher`) — БЕЗ передачи
    /// сырых сниппетов экрана модели.
    public static func properNounCandidates(from context: ScreenContextSnapshot?) -> [String] {
        guard let context else { return [] }
        let source = context.combinedContextText
        guard !source.isEmpty else { return [] }

        let pattern = #"\b[A-Z][A-Za-z0-9]+(?:[ -][A-Z][A-Za-z0-9]+){0,3}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsSource = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))

        var candidates: [String] = []
        for match in matches {
            let candidate = nsSource.substring(with: match.range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.contains(" ") || candidate.contains("-") || candidate.dropFirst().contains(where: { $0.isUppercase }) {
                candidates.append(candidate)
            }
        }
        return Array(Set(candidates))
    }

    public static func applyContextualInsertion(_ input: String, context: ScreenContextSnapshot?) -> String {
        guard let context,
              context.selectedTextSnippet == nil,
              context.isSecureTextEntry == false else { return input }
        let before = context.textBeforeCursorSnippet ?? ""
        let after = context.textAfterCursorSnippet ?? ""
        guard !before.isEmpty || !after.isEmpty else { return input }

        var result = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let beforeTrimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterTrimmed = after.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMidSentence = beforeTrimmed.last.map { !".!?\n".contains($0) } ?? false

        if isMidSentence {
            result = stripTrailingSentencePeriod(result).lowercasingFirstLetter()
        }
        if let firstAfter = afterTrimmed.first, ",.!?;:)…".contains(firstAfter) {
            result = stripTrailingSentencePeriod(result)
        }

        if let lastBefore = before.last,
           !lastBefore.isWhitespace,
           !"([{\n".contains(lastBefore),
           !result.hasPrefix(" ") {
            result = " " + result
        }

        if let firstAfter = after.first,
           !firstAfter.isWhitespace,
           !",.!?;:)…".contains(firstAfter),
           !result.hasSuffix(" ") {
            result += " "
        }

        while result.last?.isWhitespace == true {
            result.removeLast()
        }
        return result
    }

    // MARK: - Капитализация

    /// Делает заглавной первую букву текста и каждого предложения (после . ! ? и переносов).
    public static func capitalizeSentences(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var capitalizeNext = true
        for character in input {
            if capitalizeNext, character.isLetter {
                result.append(Character(String(character).uppercased()))
                capitalizeNext = false
            } else {
                result.append(character)
                if ".!?\n".contains(character) {
                    if character == ".", isNonTerminalAbbreviation(result) {
                        capitalizeNext = false
                    } else {
                        capitalizeNext = true
                    }
                }
            }
        }
        return result
    }

    private static func stripTrailingSentencePeriod(_ input: String) -> String {
        input
            .replacingOccurrences(of: #"[.。]\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whisper на тишине/шуме часто повторяет одно и то же предложение подряд —
    /// схлопываем такие повторы (сравнение без регистра и финальной пунктуации).
    private static func dropConsecutiveDuplicates(_ sentences: [String]) -> [String] {
        var result: [String] = []
        var previousKey: String?
        for sentence in sentences {
            let key = sentence
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: " .!?…"))
            guard !key.isEmpty else { continue }
            if key != previousKey {
                result.append(sentence)
                previousKey = key
            }
        }
        return result
    }

    /// Публичная обёртка для лёгкой чистки галлюцинаций без полной постобработки.
    /// Используется для live-превью стриминга, чтобы кредит-блоки не мелькали в оверлее.
    public static func stripHallucinations(_ input: String) -> String {
        removeKnownHallucinations(input)
    }

    /// whisper отдаёт текст, разбитый на сегменты переносами строк `\n`. Это технические
    /// границы СЕГМЕНТОВ, а не смысловые абзацы. Warm-server запускается с `--split-on-word`
    /// (см. `WhisperServerService`), поэтому переносы всегда попадают на границу ЦЕЛЫХ слов,
    /// а CLI-путь идёт с `-nt` и переносов не содержит вовсе. Значит КАЖДЫЙ перенос — это
    /// пробел между словами: склеиваем через пробел, а НЕ впритык, иначе слова слипаются
    /// («всеслова сливаются вместе»). Это надёжнее прежней эвристики «нет пробела = разрыв
    /// слова»: если сервер вдруг не поставит ведущий пробел на границе слов, склейка впритык
    /// слепляла целые слова — теперь этого не происходит.
    public static func normalizeTranscriptNewlines(_ input: String) -> String {
        var text = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // Любой перенос (с любыми пробелами вокруг) → один пробел.
        text = text.replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        // Пробел перед знаком препинания, если он возник из переноса («слово\n,» → «слово,»).
        text = text.replacingOccurrences(of: #" +([,.!?;:…»)])"#, with: "$1", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Удаляет известные «титровые»/медийные галлюцинации whisper. В отличие от прежней
    /// версии чистит их не только в хвосте, но и в начале/середине (whisper вставляет
    /// кредиты на тишине в любом месте записи).
    private static func removeKnownHallucinations(_ input: String) -> String {
        var text = input

        // Кредит-блоки YouTube/whisper — встречаются где угодно, занимают остаток строки.
        // Самый частый русский артефакт: «Редактор субтитров А.Семкин Корректор А.Егорова».
        // Перед маркером съедаем только пробелы/переносы (не пунктуацию предыдущего
        // предложения) — иначе у легитимной фразы пропадёт финальная точка.
        let creditPatterns = [
            // «Редактор субтитров …» (хвост строки включает «Корректор …»)
            #"(?im)\s*\bредактор\s+субтитров\b.*$"#,
            // «Субтитры сделал/делал/создал/создавал/подготовил/правил/редактировал/
            //  монтировал … » и «Субтитры предоставлены …»
            #"(?im)\s*\bсубтитры\s+(?:сделал|делал|создал|создавал|подготовил|правил|редактировал|монтировал|предоставлен)\S*\b.*$"#,
        ]
        for pattern in creditPatterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // Обобщённый хвост: «Продолжение следует», «Thanks for watching», «Сделал <имя>» и т.п.
        text = text.replacingOccurrences(
            of: #"(?i)(?:\s+|^)(?:продолжение следует|субтитры сделал[аи]? .+|субтитры создавал[аи]? .+|сделал[аи]? [а-яёa-z][а-яёa-z\s-]{1,40}|thanks for watching|to be continued)[.!?…\s]*$"#,
            with: "",
            options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedVocabularyKey(_ input: String) -> String {
        input
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func isNonTerminalAbbreviation(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return ["г.", "руб.", "стр.", "см.", "им."].contains { normalized.hasSuffix($0) }
    }

    private static func normalizeRussianDates(_ input: String) -> String {
        var text = input
        let days: [(String, Int)] = [
            ("первое", 1), ("первого", 1), ("второе", 2), ("второго", 2),
            ("третье", 3), ("третьего", 3), ("четвёртое", 4), ("четвертое", 4), ("четвёртого", 4), ("четвертого", 4),
            ("пятое", 5), ("пятого", 5), ("шестое", 6), ("шестого", 6),
            ("седьмое", 7), ("седьмого", 7), ("восьмое", 8), ("восьмого", 8),
            ("девятое", 9), ("девятого", 9), ("десятое", 10), ("десятого", 10),
            ("одиннадцатое", 11), ("одиннадцатого", 11), ("двенадцатое", 12), ("двенадцатого", 12),
            ("тринадцатое", 13), ("тринадцатого", 13), ("четырнадцатое", 14), ("четырнадцатого", 14),
            ("пятнадцатое", 15), ("пятнадцатого", 15), ("шестнадцатое", 16), ("шестнадцатого", 16),
            ("семнадцатое", 17), ("семнадцатого", 17), ("восемнадцатое", 18), ("восемнадцатого", 18),
            ("девятнадцатое", 19), ("девятнадцатого", 19), ("двадцатое", 20), ("двадцатого", 20),
            ("двадцать первое", 21), ("двадцать первого", 21), ("двадцать второе", 22), ("двадцать второго", 22),
            ("двадцать третье", 23), ("двадцать третьего", 23), ("двадцать четвёртое", 24), ("двадцать четвертое", 24),
            ("двадцать пятое", 25), ("двадцать пятого", 25), ("двадцать шестое", 26), ("двадцать шестого", 26),
            ("двадцать седьмое", 27), ("двадцать седьмого", 27), ("двадцать восьмое", 28), ("двадцать восьмого", 28),
            ("двадцать девятое", 29), ("двадцать девятого", 29), ("тридцатое", 30), ("тридцатого", 30),
            ("тридцать первое", 31), ("тридцать первого", 31)
        ]
        let months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
        let years: [(String, Int)] = [
            ("две тысячи двадцатого", 2020), ("две тысячи двадцать первого", 2021),
            ("две тысячи двадцать второго", 2022), ("две тысячи двадцать третьего", 2023),
            ("две тысячи двадцать четвёртого", 2024), ("две тысячи двадцать четвертого", 2024),
            ("две тысячи двадцать пятого", 2025), ("две тысячи двадцать шестого", 2026),
            ("две тысячи двадцать седьмого", 2027), ("две тысячи двадцать восьмого", 2028),
            ("две тысячи двадцать девятого", 2029)
        ]

        for (dayWord, day) in days {
            for month in months {
                for (yearWord, year) in years {
                    text = text.replacingOccurrences(
                        of: "\(dayWord) \(month) \(yearWord) года",
                        with: "\(day) \(month) \(year) г.",
                        options: [.caseInsensitive]
                    )
                }
            }
        }
        return text
    }

    private static func normalizeDollarAmounts(_ input: String) -> String {
        var text = input.replacingOccurrences(
            of: #"\b(\d+)\s+\1\s+(?:доллар(?:а|ов)?|usd)\b"#,
            with: #"\$$1"#,
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\b(\d+)\s+(?:доллар(?:а|ов)?|usd)\b"#,
            with: #"\$$1"#,
            options: .regularExpression
        )

        let spokenNumbers = russianNumbersUpTo99().sorted { $0.key.count > $1.key.count }
        for (phrase, value) in spokenNumbers {
            text = text.replacingOccurrences(
                of: #"\b"# + NSRegularExpression.escapedPattern(for: phrase) + #"\s+(?:доллар(?:а|ов)?|usd)\b"#,
                with: "\\$\(value)",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return text
    }

    private static func russianNumbersUpTo99() -> [String: Int] {
        let ones = [
            "ноль": 0, "один": 1, "одна": 1, "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5,
            "шесть": 6, "семь": 7, "восемь": 8, "девять": 9
        ]
        let teens = [
            "десять": 10, "одиннадцать": 11, "двенадцать": 12, "тринадцать": 13,
            "четырнадцать": 14, "пятнадцать": 15, "шестнадцать": 16, "семнадцать": 17,
            "восемнадцать": 18, "девятнадцать": 19
        ]
        let tens = [
            "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50,
            "шестьдесят": 60, "семьдесят": 70, "восемьдесят": 80, "девяносто": 90
        ]
        var result = ones.merging(teens) { current, _ in current }.merging(tens) { current, _ in current }
        for (tenWord, tenValue) in tens {
            for (oneWord, oneValue) in ones where oneValue > 0 {
                result["\(tenWord) \(oneWord)"] = tenValue + oneValue
            }
        }
        return result
    }

    private static func formatNumberedList(_ input: String) -> String {
        let markerPattern = #"\b(?:(?:пункт|номер)\s+(один|два|три|четыре|пять|шесть|семь|восемь|девять|десять)|во[- ]?(первых|вторых|третьих|четв[её]ртых|пятых|шестых|седьмых|восьмых|девятых|десятых))\b"#
        guard let regex = try? NSRegularExpression(pattern: markerPattern, options: [.caseInsensitive]) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, range: range)
        guard matches.count >= 2 else { return input }

        let numberByWord = [
            "один": 1, "два": 2, "три": 3, "четыре": 4, "пять": 5,
            "шесть": 6, "семь": 7, "восемь": 8, "девять": 9, "десять": 10,
            "первых": 1, "вторых": 2, "третьих": 3, "четвёртых": 4, "четвертых": 4,
            "пятых": 5, "шестых": 6, "седьмых": 7, "восьмых": 8, "девятых": 9,
            "десятых": 10
        ]
        var lines: [String] = []
        let prefixRange = NSRange(location: 0, length: matches[0].range.location)
        if let prefix = Range(prefixRange, in: input) {
            let trimmed = String(input[prefix]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append(trimmed) }
        }

        for (index, match) in matches.enumerated() {
            let markerRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard let wordRange = Range(markerRange, in: input),
                  let number = numberByWord[String(input[wordRange]).lowercased()] else { continue }
            let contentStart = match.range.location + match.range.length
            let contentEnd = index + 1 < matches.count ? matches[index + 1].range.location : input.utf16.count
            guard contentEnd > contentStart,
                  let contentRange = Range(NSRange(location: contentStart, length: contentEnd - contentStart), in: input) else { continue }
            let item = capitalizeFirstLetter(
                String(input[contentRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t.,;:"))
            )
            guard !item.isEmpty else { continue }
            lines.append("\(number). \(item)")
        }

        return lines.count > 1 ? lines.joined(separator: "\n") : input
    }

    private static func capitalizeFirstLetter(_ input: String) -> String {
        var output = ""
        var didCapitalize = false
        for character in input {
            if !didCapitalize, character.isLetter {
                output.append(Character(String(character).uppercased()))
                didCapitalize = true
            } else {
                output.append(character)
            }
        }
        return output
    }

    private static func groupSentencesIntoSemanticParagraphs(_ sentences: [String], softMax: Int) -> [[String]] {
        guard !sentences.isEmpty else { return [] }

        var paragraphs: [[String]] = [[]]
        for (index, sentence) in sentences.enumerated() {
            let current = paragraphs[paragraphs.count - 1]
            let remaining = sentences.count - index  // включая текущее предложение
            // Разрыв по смыслу: маркер перехода + в текущем абзаце уже ≥2 предложения.
            let semanticBreak = shouldStartSemanticParagraph(sentence) && current.count >= 2
            // Страховка от «простыни»: длинный абзац рвём, но только если дальше
            // остаётся ≥2 предложения — иначе получим одинокий хвост.
            let lengthBreak = current.count >= softMax && remaining >= 2

            if !current.isEmpty, semanticBreak || lengthBreak {
                paragraphs.append([])
            }
            paragraphs[paragraphs.count - 1].append(sentence)
        }
        return paragraphs
    }

    /// Маркеры реального смыслового перехода в начале предложения. Сознательно БЕЗ
    /// «голых» порядковых (первое/второе/третье) — это часто обычный текст, а не
    /// нумерация. И без слишком частых связок (ещё, при этом, однако), чтобы не
    /// рвать абзацы «просто так». Распознаются только в начале предложения.
    private static func shouldStartSemanticParagraph(_ sentence: String) -> Bool {
        let normalized = sentence
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let markers = [
            // продолжение / переход
            "также", "теперь", "далее", "дальше",
            // добавление новой мысли
            "кроме того", "к тому же", "более того", "помимо этого",
            // контраст / смена ракурса
            "с другой стороны", "что касается",
            // переход к новой теме
            "перейдём", "перейдем",
            // нумерация (безопасные формы)
            "во-первых", "во-вторых", "в-третьих", "в-четвёртых", "в-четвертых",
            // итог
            "итак", "в итоге", "в результате", "в заключение", "таким образом", "наконец",
            // english
            "also", "another", "next", "finally", "moreover", "furthermore",
            "in addition", "on the other hand", "in conclusion"
        ]
        return markers.contains { marker in
            normalized == marker || normalized.hasPrefix(marker + " ") || normalized.hasPrefix(marker + ",")
        }
    }

    private static func formatEmailGreeting(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let greetings = ["привет", "здравствуйте", "добрый день", "доброе утро", "добрый вечер", "hello", "hi"]
        guard let greeting = greetings.first(where: { lowercased == $0 || lowercased.hasPrefix($0 + " ") }) else {
            return ensureSentencePunctuation(trimmed)
        }

        let rest = String(trimmed.dropFirst(greeting.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.isEmpty {
            return ensureSentencePunctuation(trimmed)
        }
        let capitalizedGreeting = String(trimmed.prefix(greeting.count))
        return "\(capitalizedGreeting), \(rest.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?")))!".replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
    }

    private static func splitTrailingEmailSignoff(_ lines: inout [String]) {
        guard let last = lines.last else { return }
        let signoffs = ["спасибо", "с уважением", "thanks", "thank you", "best", "regards"]
        for signoff in signoffs {
            let pattern = #"(?i)^(.+[.!?])\s+("# + NSRegularExpression.escapedPattern(for: signoff) + #")[.!?]?$"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(last.startIndex..<last.endIndex, in: last)
            guard let match = regex.firstMatch(in: last, range: range),
                  match.numberOfRanges == 3,
                  let bodyRange = Range(match.range(at: 1), in: last),
                  let signoffRange = Range(match.range(at: 2), in: last) else {
                continue
            }
            lines.removeLast()
            lines.append(String(last[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append(String(last[signoffRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }
    }

    private static func formatEmailSignoff(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .,!?:;"))
        let signoffs = ["спасибо", "с уважением", "thanks", "thank you", "best", "regards"]
        guard signoffs.contains(lowercased) else {
            return ensureSentencePunctuation(trimmed)
        }
        return ensureSentencePunctuation(trimmed)
    }

    private static func ensureSentencePunctuation(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return trimmed }
        if ".!?".contains(last) {
            return trimmed
        }
        return trimmed + "."
    }

    private static func splitSentences(_ input: String) -> [String] {
        let pattern = #"[^.!?。！？]+[.!?。！？]+(?:["»”])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [input]
        }

        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, range: range)
        var sentences = matches.compactMap { match -> String? in
            guard let sentenceRange = Range(match.range, in: input) else { return nil }
            return String(input[sentenceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let lastMatch = matches.last,
           let lastRange = Range(lastMatch.range, in: input),
           lastRange.upperBound < input.endIndex {
            let tail = String(input[lastRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                sentences.append(tail)
            }
        }

        return sentences.isEmpty ? [input] : sentences
    }
}

private extension String {
    func lowercasingFirstLetter() -> String {
        guard let first else { return self }
        return String(first).lowercased() + dropFirst()
    }
}
