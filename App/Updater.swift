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

    /// Check when the app opens: only speaks up when there's a new version the user
    /// hasn't chosen to skip.
    static func checkOnLaunch() {
        Task {
            try? await Task.sleep(for: .seconds(2))   // let the window appear first
            await check(userInitiated: false)
        }
    }

    private static let skippedKey = "skippedUpdateVersion"

    static func check(userInitiated: Bool) async {
        guard let repo, let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            if userInitiated { alert(L("还没有设置更新地址"), L("这个版本不知道去哪里检查更新。")) }
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                if userInitiated { alert(L("已经是最新版本"), L("当前版本 \(currentVersion)，还没有发布过更新。")) }
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if isNewer(latest, than: currentVersion) {
                // Automatic checks stay quiet about a version the user chose to skip.
                if !userInitiated, UserDefaults.standard.string(forKey: skippedKey) == latest { return }
                let notes = readableNotes(release.body ?? "").prefix(600)
                let a = NSAlert()
                a.messageText = L("有新版本 \(latest)（当前 \(currentVersion)）")
                a.informativeText = notes.isEmpty ? L("到下载页面获取新版本。") : String(notes)
                a.addButton(withTitle: L("去下载"))
                a.addButton(withTitle: L("以后再说"))
                a.addButton(withTitle: L("跳过这个版本"))
                NSApp.activate(ignoringOtherApps: true)
                switch a.runModal() {
                case .alertFirstButtonReturn:
                    if let page = URL(string: release.html_url) { NSWorkspace.shared.open(page) }
                case .alertThirdButtonReturn:
                    UserDefaults.standard.set(latest, forKey: skippedKey)
                default:
                    break
                }
            } else if userInitiated {
                alert(L("已经是最新版本"), L("当前版本 \(currentVersion)。"))
            }
        } catch {
            if userInitiated { alert(L("检查更新失败"), L("请检查网络后再试。\n\(error.localizedDescription)")) }
        }
    }

    /// Release notes are Markdown with a Chinese part and an English part separated by
    /// "---". Shows the part for the app's language as plain text.
    static func readableNotes(_ markdown: String) -> String {
        let parts = markdown.components(separatedBy: "\n---\n")
        var text = parts.count > 1 ? (AppLanguage.isEnglish ? parts[1] : parts[0]) : markdown
        text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("- ") ? "• " + t.dropFirst(2) : t
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
