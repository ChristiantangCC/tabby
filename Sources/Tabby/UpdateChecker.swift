import Foundation
import Combine

/// Asks GitHub whether a newer release exists. It only tells the user; it never downloads anything itself.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        let version: String
        let url: URL
    }

    /// Set when GitHub has a release newer than the running app.
    @Published private(set) var available: Release?

    private let endpoint = URL(string: "https://api.github.com/repos/ChristiantangCC/tabby/releases/latest")!
    private var timer: Timer?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Checks now, then once a day, while the "Check for updates" setting is on.
    func start() {
        timer?.invalidate()
        guard UserDefaults.standard.object(forKey: Prefs.checkUpdates) as? Bool ?? true else {
            available = nil
            return
        }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func check() {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = json["tag_name"] as? String,
                let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            else { return }

            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let newer = Self.isNewer(version, than: Self.currentVersion)
            DispatchQueue.main.async {
                self?.available = newer ? Release(version: version, url: page) : nil
            }
        }.resume()
    }

    /// Numeric, part-by-part comparison: 0.10.0 is newer than 0.9.3.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
