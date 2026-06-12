import AppKit
import Foundation
import LyraVoiceCore

enum DiagnosticsLog {
    private static let queue = DispatchQueue(label: "local.lyravoice.diagnostics")

    /// Управляется настройкой «Записывать диагностический лог». По умолчанию включено.
    nonisolated(unsafe) static var isEnabled = true

    private static var fileURL: URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(AppBrand.applicationSupportDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("diagnostics.log")
    }

    /// Открывает `diagnostics.log` в Finder (создаёт пустой файл, если его ещё нет).
    static func revealInFinder() {
        let url = fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func write(_ message: String) {
        guard isEnabled else { return }
        queue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            guard let data = "\(timestamp) \(message)\n".data(using: .utf8) else { return }

            let url = fileURL
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: url)
            }
        }
    }

    static func byteCountDescription(for url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return "unavailable"
        }
        return "\(size.int64Value)"
    }
}
