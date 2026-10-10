import AppKit

/// Checks GitHub Releases for a newer version. The repository ("owner/name") and the
/// current version come from Info.plist (written by build.sh).
@MainActor
enum Updater {
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    static var repo: String? {
        (Bundle.main.object(forInfoDictionaryKey: "BPUpdateRepo") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private struct Release: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: String
    }

    /// Daily background check: only speaks up when there's an update.
    static func checkDaily() {
        let key = "lastUpdateCheck"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 else { return }
        UserDefaults.standard.set(Date(), forKey: key)
        Task { await check(userInitiated: false) }
    }

    static func check(userInitiated: Bool) async {
        guard let repo, let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            if userInitiated { alert("还没有设置更新地址", "这个版本不知道去哪里检查更新。") }
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                if userInitiated { alert("已经是最新版本", "当前版本 \(currentVersion)，还没有发布过更新。") }
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if isNewer(latest, than: currentVersion) {
                let notes = (release.body ?? "").prefix(600)
                let a = NSAlert()
                a.messageText = "有新版本 \(latest)（当前 \(currentVersion)）"
                a.informativeText = notes.isEmpty ? "到下载页面获取新版本。" : String(notes)
                a.addButton(withTitle: "去下载")
                a.addButton(withTitle: "以后再说")
                NSApp.activate(ignoringOtherApps: true)
                if a.runModal() == .alertFirstButtonReturn, let page = URL(string: release.html_url) {
                    NSWorkspace.shared.open(page)
                }
            } else if userInitiated {
                alert("已经是最新版本", "当前版本 \(currentVersion)。")
            }
        } catch {
            if userInitiated { alert("检查更新失败", "请检查网络后再试。\n\(error.localizedDescription)") }
        }
    }

    /// Compares dotted version numbers ("1.10.0" > "1.9.2").
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
