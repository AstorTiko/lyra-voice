import Foundation

public struct WhisperCommand: Equatable, Sendable {
    public let binaryURL: URL
    public let modelURL: URL
    public let audioURL: URL
    public let language: String
    public let initialPrompt: String
    public let threads: Int
    public let beamSize: Int
    public let suppressNonSpeech: Bool
    public let carryInitialPrompt: Bool
    /// Включить Voice Activity Detection — отсекает тишину/паузы, предотвращает галлюцинации.
    public let vadEnabled: Bool
    /// Путь к GGML-модели Silero VAD. Если nil — VAD пропускается без ошибки.
    public let vadModelURL: URL?
    public let extraArguments: [String]

    public init(
        binaryURL: URL,
        modelURL: URL,
        audioURL: URL,
        language: String,
        initialPrompt: String = "",
        threads: Int = WhisperCommand.recommendedThreadCount,
        beamSize: Int = 5,
        suppressNonSpeech: Bool = true,
        carryInitialPrompt: Bool = true,
        vadEnabled: Bool = false,
        vadModelURL: URL? = nil,
        extraArguments: [String] = []
    ) {
        self.binaryURL = binaryURL
        self.modelURL = modelURL
        self.audioURL = audioURL
        self.language = language
        self.initialPrompt = initialPrompt
        self.threads = threads
        self.beamSize = beamSize
        self.suppressNonSpeech = suppressNonSpeech
        self.carryInitialPrompt = carryInitialPrompt
        self.vadEnabled = vadEnabled
        self.vadModelURL = vadModelURL
        self.extraArguments = extraArguments
    }

    /// Разумное число потоков: все производительные ядра, но не меньше 4.
    public static var recommendedThreadCount: Int {
        max(4, ProcessInfo.processInfo.activeProcessorCount)
    }

    public var executablePath: String {
        binaryURL.path
    }

    public var arguments: [String] {
        var args = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-l", language,
            "-t", "\(threads)",
            "-bs", "\(beamSize)",
            "-bo", "\(beamSize)"
        ]

        let trimmedPrompt = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            args += ["--prompt", initialPrompt]
            if carryInitialPrompt {
                // Применять промпт ко всем окнам, а не только к первому —
                // заметно ровнее пунктуация на длинной диктовке.
                args.append("--carry-initial-prompt")
            }
        }

        if suppressNonSpeech {
            // Убирает [музыка], (аплодисменты) и прочие галлюцинации на тишине.
            args.append("-sns")
        }

        if vadEnabled, let vadURL = vadModelURL {
            // VAD режет паузы между мыслями → убирает галлюцинации и повторы на тишине.
            // Параметры настроены для диктовки: пауза 2 с разделяет сегменты,
            // padding 400 мс сохраняет начало/конец слова.
            args += [
                "--vad",
                "-vm", vadURL.path,
                // threshold 0.35 (вместо дефолтных 0.5): тихая/начитанная вполголоса речь
                // даёт более низкую вероятность речи у silero — на 0.5 целые короткие
                // диктовки отсекались как «тишина» (0 символов, диктовка терялась). 0.35
                // консервативно ловит тихую речь, не впуская явный шумовой пол.
                "--vad-threshold", "0.35",
                "--vad-min-silence-duration-ms", "2000",
                "--vad-speech-pad-ms", "400",
                "--vad-max-speech-duration-s", "30"
            ]
        }

        args += [
            "-nt",
            "-np"
        ]

        return args + extraArguments
    }
}
