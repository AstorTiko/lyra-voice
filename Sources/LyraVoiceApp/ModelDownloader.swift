import Foundation

/// Прогресс скачивания модели: доля 0…1 и абсолютные байты (для «X из Y МБ»).
struct ModelDownloadProgress: Sendable {
    let fraction: Double
    let bytesWritten: Int64
    let bytesExpected: Int64
}

final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var progressHandler: (@Sendable (ModelDownloadProgress) -> Void)?

    func download(from url: URL, progress: @Sendable @escaping (ModelDownloadProgress) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.progressHandler = progress
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        progressHandler?(ModelDownloadProgress(
            fraction: fraction,
            bytesWritten: totalBytesWritten,
            bytesExpected: totalBytesExpectedToWrite
        ))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // `location` валиден только внутри этого вызова: система удалит файл
        // сразу после возврата из делегата. Переносим его в стабильное место
        // синхронно, до того как отдать URL наружу через continuation.
        let response = downloadTask.response as? HTTPURLResponse
        if let response, !(200...299).contains(response.statusCode) {
            continuation?.resume(throwing: ModelDownloaderError.badStatus(response.statusCode))
            cleanup(session)
            return
        }

        let safeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyraVoiceDownloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(
                at: safeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: safeURL.path) {
                try FileManager.default.removeItem(at: safeURL)
            }
            try FileManager.default.moveItem(at: location, to: safeURL)
            continuation?.resume(returning: safeURL)
        } catch {
            continuation?.resume(throwing: error)
        }
        cleanup(session)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        cleanup(session)
    }

    private func cleanup(_ session: URLSession) {
        continuation = nil
        progressHandler = nil
        session.invalidateAndCancel()
    }
}

enum ModelDownloaderError: LocalizedError {
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case let .badStatus(code):
            return "Download failed with HTTP status \(code)."
        }
    }
}
