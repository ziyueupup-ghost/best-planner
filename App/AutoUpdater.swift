import AppKit
import CryptoKit
import SwiftUI

/// One-click update: downloads the new version from GitHub Releases, checks it, swaps it
/// in for the running app and reopens. Downloaded by the app itself (not a browser), so
/// macOS doesn't quarantine it and there's no Gatekeeper prompt for the new version.
///
/// Checks before installing anything:
///   • the zip's SHA-256 matches the ".sha256" file published with it
///   • the unzipped app has our bundle id and is the expected, newer version
///   • its code signature is intact (codesign --verify --deep --strict)
/// If any step fails, nothing is replaced and the download page is offered instead.
@MainActor
enum AutoUpdater {
    static func zipName(_ version: String) -> String { "BestPlanner-\(version).zip" }

    /// The release has both the zip and its checksum, and this copy of the app can be replaced.
    static func canInstall(_ release: Updater.Release) -> Bool {
        let version = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let names = Set((release.assets ?? []).map(\.name))
        return names.contains(zipName(version)) && names.contains(zipName(version) + ".sha256") && canReplaceSelf
    }

    private static var canReplaceSelf: Bool {
        let app = Bundle.main.bundleURL
        return FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
            && FileManager.default.isWritableFile(atPath: app.path)
    }

    static func install(_ release: Updater.Release, version: String) {
        let progress = UpdateProgressWindow()
        progress.show(L("正在下载 \(version)…"))
        Task {
            do {
                let newApp = try await download(release, version: version, progress: progress)
                progress.update(L("正在安装…"))
                let current = Bundle.main.bundleURL
                _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)
                progress.update(L("安装完成，正在重新打开…"))
                BoardStore.shared.flush()
                let path = current.path
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
                try relaunch.run()
                NSApp.terminate(nil)
            } catch {
                progress.close()
                let a = NSAlert()
                a.messageText = L("没能自动更新")
                a.informativeText = L("可以到下载页面手动下载新版本。\n\(error.localizedDescription)")
                a.addButton(withTitle: L("去下载"))
                a.addButton(withTitle: L("取消"))
                if a.runModal() == .alertFirstButtonReturn, let page = URL(string: release.html_url) {
                    NSWorkspace.shared.open(page)
                }
            }
        }
    }

    enum UpdateError: LocalizedError {
        case missingFile, checksumMismatch, notOurApp, wrongVersion, badSignature

        var errorDescription: String? {
            switch self {
            case .missingFile: L("下载的文件不完整。")
            case .checksumMismatch: L("下载的文件校验不通过（可能下载出错或被改动过）。")
            case .notOurApp: L("下载的不是 Best Planner。")
            case .wrongVersion: L("下载的版本号不对。")
            case .badSignature: L("新版本的签名校验不通过。")
            }
        }
    }

    /// Downloads, verifies and unzips; returns the new app bundle (in a temporary folder).
    private static func download(_ release: Updater.Release, version: String, progress: UpdateProgressWindow) async throws -> URL {
        let assets = release.assets ?? []
        guard let zipURL = assets.first(where: { $0.name == zipName(version) }).flatMap({ URL(string: $0.browser_download_url) }),
              let sumURL = assets.first(where: { $0.name == zipName(version) + ".sha256" }).flatMap({ URL(string: $0.browser_download_url) })
        else { throw UpdateError.missingFile }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("BestPlannerUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let (downloaded, _) = try await URLSession.shared.download(from: zipURL)
        let zip = work.appendingPathComponent(zipName(version))
        try FileManager.default.moveItem(at: downloaded, to: zip)
        let (sumData, _) = try await URLSession.shared.data(from: sumURL)

        progress.update(L("正在校验…"))
        let expected = String(decoding: sumData, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased()
        let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard expected == actual else { throw UpdateError.checksumMismatch }

        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let app = work.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { throw UpdateError.missingFile }
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else { throw UpdateError.notOurApp }
        guard let newVersion = info["CFBundleShortVersionString"] as? String, newVersion == version,
              Updater.isNewer(newVersion, than: Updater.currentVersion) else { throw UpdateError.wrongVersion }
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        } catch {
            throw UpdateError.badSignature
        }
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw UpdateError.missingFile }
    }
}

/// A small floating window with a spinner while the update downloads and installs.
@MainActor
final class UpdateProgressWindow {
    private final class Model: ObservableObject { @Published var text = "" }
    private let model = Model()
    private var window: NSWindow?

    func show(_ text: String) {
        model.text = text
        let view = ProgressContent(model: model).frame(width: 320).padding(20)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 110),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Best Planner"
        w.contentView = NSHostingView(rootView: view)
        w.level = .floating
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    func update(_ text: String) { model.text = text }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    private struct ProgressContent: View {
        @ObservedObject var model: Model
        var body: some View {
            HStack(spacing: 14) {
                ProgressView().controlSize(.small)
                Text(model.text)
                Spacer()
            }
        }
    }
}
