import Foundation
import LyraVoiceCore

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

enum UpdateCheckResult: CustomStringConvertible {
    case upToDate
    case updateAvailable(version: String, url: URL)
    case failed

    var description: String {
        switch self {
        case .upToDate: return "upToDate"
        case .updateAvailable(let version, _): return "updateAvailable(\(version))"
        case .failed: return "failed"
        }
    }
}

@MainActor
enum UpdateChecker {
    static func checkLatestRelease(currentVersion: String) async -> UpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/\(AppBrand.updateRepository)/releases/latest") else {
            return .failed
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if isNewer(latest, than: currentVersion), let releaseURL = URL(string: release.htmlURL) {
                return .updateAvailable(version: latest, url: releaseURL)
            }
            return .upToDate
        } catch {
            return .failed
        }
    }

    /// Сравнение версий вида "1.2.3" — посегментно, по числам.
    private static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
