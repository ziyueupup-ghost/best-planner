import AppKit
import SwiftUI

/// 跟随系统 / 中文 / English, for the app menu and the toolbar 🌐 button.
/// Switching saves the choice and offers to reopen the app (text is set at launch).
struct LanguageChoices: View {
    var body: some View {
        choice(.system, L("跟随系统"))
        choice(.chinese, "中文")
        choice(.english, "English")
    }

    private func choice(_ language: AppLanguage, _ title: String) -> some View {
        Button {
            guard AppLanguage.choice != language else { return }
            AppLanguage.set(language)
            let alert = NSAlert()
            alert.messageText = L("重新打开 Best Planner 后生效")
            alert.addButton(withTitle: L("现在重新打开"))
            alert.addButton(withTitle: L("稍后"))
            if alert.runModal() == .alertFirstButtonReturn { Self.relaunch() }
        } label: {
            if AppLanguage.choice == language { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    static func relaunch() {
        BoardStore.shared.flush()
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
