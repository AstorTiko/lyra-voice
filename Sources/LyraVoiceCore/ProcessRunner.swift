import Foundation

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
}

public final class ProcessRunner {
    public init() {}

    public func run(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Читаем пайпы параллельно с работой процесса. Иначе на выводе
        // больше размера буфера пайпа (~64 КБ) процесс блокируется на записи,
        // и длинная транскрипция уходит в ложный таймаут.
        let collector = OutputCollector()
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                collector.appendOutput(data)
            }
        }
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                collector.appendError(data)
            }
        }

        try process.run()

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        if process.isRunning {
            process.terminate()
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            throw ProcessRunnerError.timedOut
        }

        process.waitUntilExit()

        // Дочитываем всё, что осталось в пайпах после выхода процесса.
        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil
        collector.appendOutput(outputHandle.readDataToEndOfFile())
        collector.appendError(errorHandle.readDataToEndOfFile())

        let (outputData, errorData) = collector.snapshot()
        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? ""
        )
    }
}

/// Потокобезопасный накопитель вывода: `readabilityHandler` вызывается
/// на фоновой очереди, поэтому доступ к буферам сериализуем через lock.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var error = Data()

    func appendOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        output.append(data)
    }

    func appendError(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        error.append(data)
    }

    func snapshot() -> (Data, Data) {
        lock.lock(); defer { lock.unlock() }
        return (output, error)
    }
}

public enum ProcessRunnerError: Error, Equatable {
    case timedOut
}
