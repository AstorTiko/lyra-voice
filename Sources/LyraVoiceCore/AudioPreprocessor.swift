import Foundation

/// Предобработка аудиофайла перед передачей в Whisper.
///
/// ВАЖНО: обработка намеренно консервативна. Запись и так пишется в 16 кГц/моно/PCM16,
/// а Whisper нормализует громкость внутри себя. Агрессивная обработка (вырезание пауз
/// внутри речи, двойная динамическая компрессия) доказуемо РУШИТ распознавание —
/// склеивает слова, поднимает шумовой пол и искажает термины. Поэтому здесь:
///   • тишина режется ТОЛЬКО по краям записи, паузы внутри речи не трогаются;
///   • один мягкий проход громкости, без каскада нормализаторов.
public enum AudioPreprocessor {
    public static let defaultFFmpegPath = "/opt/homebrew/bin/ffmpeg"

    /// Предобрабатывает WAV-файл и возвращает URL обработанной копии.
    /// При недоступном ffmpeg или ошибке — возвращает исходный URL без изменений.
    ///
    /// - Parameters:
    ///   - inputURL: исходный WAV-файл
    ///   - trimSilence: убрать тишину ТОЛЬКО в начале и конце (паузы внутри речи сохраняются)
    ///   - normalize: один мягкий проход loudnorm (-18 LUFS) для тихих микрофонов
    ///   - ffmpegPath: путь к бинарю ffmpeg
    public static func preprocess(
        inputURL: URL,
        trimSilence: Bool = true,
        normalize: Bool = true,
        ffmpegPath: String = defaultFFmpegPath
    ) -> URL {
        guard trimSilence || normalize else { return inputURL }
        guard FileManager.default.fileExists(atPath: ffmpegPath) else { return inputURL }

        let outputURL = inputURL.deletingLastPathComponent()
            .appendingPathComponent("pp_" + inputURL.lastPathComponent)

        var filters: [String] = []
        if trimSilence {
            // Триммим тишину ТОЛЬКО по краям: убираем ведущую, разворачиваем,
            // убираем «ведущую» развёрнутого (= замыкающую), разворачиваем обратно.
            // Паузы между мыслями внутри речи НЕ трогаем — иначе склеиваются слова.
            // Порог -50 dBFS консервативный, чтобы не срезать тихие начала/концы слов.
            let trimLeading = "silenceremove=start_periods=1:start_silence=0:start_threshold=-50dB:detection=peak"
            filters.append(trimLeading)
            filters.append("areverse")
            filters.append(trimLeading)
            filters.append("areverse")
        }
        if normalize {
            // Один мягкий проход громкости к -18 LUFS. Без dynaudnorm — каскад
            // нормализаторов поднимает шумовой пол и искажает речь (хуже для Whisper).
            filters.append("loudnorm=I=-18:TP=-2:LRA=11")
        }

        let filterChain = filters.joined(separator: ",")
        let args = ["-y", "-i", inputURL.path,
                    "-af", filterChain,
                    "-ar", "16000", "-ac", "1",
                    outputURL.path]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpegPath)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return inputURL
        }

        guard proc.terminationStatus == 0,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            return inputURL
        }
        return outputURL
    }

    /// Обратная совместимость: только нормализация громкости.
    @available(*, deprecated, renamed: "preprocess(inputURL:trimSilence:normalize:ffmpegPath:)")
    public static func normalize(inputURL: URL, ffmpegPath: String = defaultFFmpegPath) -> URL {
        preprocess(inputURL: inputURL, trimSilence: false, normalize: true, ffmpegPath: ffmpegPath)
    }
}
