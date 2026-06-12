import Foundation

public final class WhisperCLITranscriber {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func transcribe(command: WhisperCommand, timeoutSeconds: TimeInterval = 120) throws -> String {
        let result = try runner.run(
            executablePath: command.executablePath,
            arguments: command.arguments,
            timeoutSeconds: timeoutSeconds
        )

        guard result.exitCode == 0 else {
            throw WhisperCLITranscriberError.failed(
                exitCode: result.exitCode,
                stderr: result.standardError
            )
        }

        return TextPostProcessor.dictationCleanup(result.standardOutput)
    }
}

public enum WhisperCLITranscriberError: Error, Equatable {
    case failed(exitCode: Int32, stderr: String)
}
