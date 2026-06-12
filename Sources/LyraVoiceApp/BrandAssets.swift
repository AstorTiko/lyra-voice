import AppKit
import LyraVoiceCore

@MainActor
enum BrandAssets {
    static func logoImage(size: CGFloat? = nil) -> NSImage? {
        guard let url = resourceURL(named: AppBrand.logoImageFileName),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        if let size {
            image.size = NSSize(width: size, height: size)
        }
        return image
    }

    private static func resourceURL(named fileName: String) -> URL? {
        if let url = Bundle.main.url(forResource: fileNameWithoutExtension(fileName), withExtension: fileExtension(fileName)) {
            return url
        }

        if let url = Bundle.main.resourceURL?.appendingPathComponent(fileName),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Assets/Brand", isDirectory: true)
            .appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }

        return nil
    }

    private static func fileNameWithoutExtension(_ fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    private static func fileExtension(_ fileName: String) -> String {
        (fileName as NSString).pathExtension
    }
}
