import SwiftUI

@main
struct PlannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = BoardStore.shared
    @AppStorage(FontScale.storageKey) private var fontScale = 1.0

    var body: some Scene {
        WindowGroup("Best Planner", id: "main") {
            BoardView()
                .environmentObject(store)
                .appFontSize()
                .frame(minWidth: 480, minHeight: 360)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L("检查更新…")) { Task { await Updater.check(userInitiated: true) } }
                Divider()
                Button(store.usesICloud ? L("关闭 iCloud 云盘同步…") : L("使用 iCloud 云盘同步…")) {
                    NotificationCenter.default.post(name: .iCloudToggleRequested, object: nil)
                }
                Button(L("打开备份文件夹")) {
                    try? FileManager.default.createDirectory(at: PlannerStorage.backupDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(PlannerStorage.backupDirectory)
                }
                Menu(L("语言 / Language")) { LanguageChoices() }
            }
            CommandGroup(replacing: .newItem) {
                Button(L("新建任务")) {
                    NotificationCenter.default.post(name: .newTaskRequested, object: nil)
                }
                .keyboardShortcut("n")
            }
            CommandGroup(after: .toolbar) {
                Divider()
                Button(L("放大字体")) { fontScale = FontScale.clamped(fontScale + FontScale.step) }
                    .keyboardShortcut("=", modifiers: .command)
                Button(L("缩小字体")) { fontScale = FontScale.clamped(fontScale - FontScale.step) }
                    .keyboardShortcut("-", modifiers: .command)
                Button(L("实际大小")) { fontScale = 1.0 }
                    .keyboardShortcut("0", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button(L("管理状态和标签…")) {
                    NotificationCenter.default.post(name: .settingsRequested, object: nil)
                }
                .keyboardShortcut(",")
                Button(L("最近删除…")) {
                    NotificationCenter.default.post(name: .trashRequested, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                Divider()
                Button(L("快速添加（全局 ⌃⌥N）…")) { QuickAddController.shared.show() }
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(store)
        } label: {
            MenuBarLabel()
        }
    }
}

extension Notification.Name {
    static let newTaskRequested = Notification.Name("PlannerNewTaskRequested")
    static let settingsRequested = Notification.Name("PlannerSettingsRequested")
    static let trashRequested = Notification.Name("PlannerTrashRequested")
    static let iCloudToggleRequested = Notification.Name("PlannerICloudToggleRequested")
    /// object: task id — opens that task's editor (e.g. right after duplicating it).
    static let openTaskRequested = Notification.Name("PlannerOpenTaskRequested")
}
