import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// Floating quick-add box (like Spotlight): opened by the global shortcut ⌃⌥N or the
/// menu bar icon. It can take keyboard input without bringing the main window forward.
@MainActor
final class QuickAddController: NSObject, NSWindowDelegate {
    static let shared = QuickAddController()
    private var panel: NSPanel?

    /// Clicking anywhere else closes it, like Spotlight.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in self.hide() }
    }

    func show() {
        if panel == nil {
            let p = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 150),
                                 styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                                 backing: .buffered, defer: false)
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.standardWindowButton(.closeButton)?.isHidden = true
            p.standardWindowButton(.miniaturizeButton)?.isHidden = true
            p.standardWindowButton(.zoomButton)?.isHidden = true
            p.delegate = self
            p.contentView = NSHostingView(rootView: QuickAddView(close: { [weak self] in self?.hide() })
                .environmentObject(BoardStore.shared)
                .appFontSize())
            panel = p
        }
        guard let panel else { return }
        // Top third of the screen with the mouse, like Spotlight.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - f.height / 4 - panel.frame.height))
        }
        NotificationCenter.default.post(name: .quickAddReset, object: nil)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }
}

/// A non-activating panel that can still become key (so the text field gets typing).
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

extension Notification.Name {
    static let quickAddReset = Notification.Name("PlannerQuickAddReset")
}

struct QuickAddView: View {
    @EnvironmentObject private var store: BoardStore
    let close: () -> Void
    @State private var text = ""
    @State private var added: String?
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = QuickParse(text, board: store.board)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .scaledFont(.title2)
                    .foregroundStyle(Color.accentColor)
                TextField("", text: $text, prompt: Text(L("交初稿 明天下午3点 #论文修改 !紧急 @进行中")))
                    .textFieldStyle(.plain)
                    .scaledFont(.title3)
                    .focused($focused)
                    .onSubmit { submit(parsed) }
            }
            preview(parsed)
            HStack {
                Text(L("#标签  !优先级  @状态  明天/周五/10月15日  下午3点（带时间=提醒）"))
                    .scaledFont(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(L("↩ 添加  esc 关闭"))
                    .scaledFont(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 560)
        .background(.regularMaterial)
        .onExitCommand(perform: close)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .quickAddReset)) { _ in
            text = ""
            added = nil
            focused = true
        }
    }

    @ViewBuilder
    private func preview(_ p: QuickParse) -> some View {
        HStack(spacing: 8) {
            if let added, text.isEmpty {
                Label(L("已添加「\(added)」，可以继续输入下一个"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if text.isEmpty {
                Text(L("输入任务，回车添加")).foregroundStyle(.secondary)
            } else {
                let column = p.columnID.flatMap { store.board.column($0) } ?? store.columns.first
                if let column { chip(column.icon.isEmpty ? column.name : "\(column.icon) \(column.name)", .secondary) }
                let level = store.board.priorities.first { $0.id == (p.priorityID ?? store.board.defaultPriorityID) }
                if let level, p.priorityID != nil { chip(level.label, level.color) }
                ForEach(p.tagNames, id: \.self) { name in
                    if let tag = store.tags.first(where: { $0.name == name }) {
                        TagChip(tag: tag, small: true)
                    } else {
                        chip(L("#\(name)（新标签）"), .secondary)
                    }
                }
                if let d = p.date {
                    chip("\(p.dateKind == .reminder ? L("⏰ 提醒") : L("📌 截止")) "
                         + (p.hasTime ? d.formatted(.dateTime.month().day().weekday().hour().minute())
                                      : d.formatted(.dateTime.month().day().weekday())),
                         p.dateKind.color)
                }
            }
            Spacer()
        }
        .scaledFont(.caption)
        .frame(minHeight: 20)
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color == .secondary ? Color.primary : color)
    }

    private func submit(_ p: QuickParse) {
        guard !p.title.isEmpty else { return }
        store.quickAdd(p)
        added = p.title
        text = ""
    }
}

/// System-wide ⌃⌥N via Carbon hot keys (works without accessibility permission).
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register() {
        guard hotKey == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { QuickAddController.shared.toggle() }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x42504C4E), id: 1)   // "BPLN"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { NSLog("Planner: could not register ⌃⌥N (\(status))") }
    }
}

/// The menu bar icon, or the focus countdown while a focus session runs.
struct MenuBarLabel: View {
    @ObservedObject private var timer = FocusTimer.shared

    var body: some View {
        if timer.isRunning {
            Text("🍅 \(timer.label)").monospacedDigit()
        } else {
            Image(systemName: "checklist")
        }
    }
}

/// Menu bar icon: quick add, today's open tasks, open the window, launch at login.
struct MenuBarContent: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Button(L("快速添加任务…")) { QuickAddController.shared.show() }
            .keyboardShortcut("n", modifiers: [.control, .option])
        FocusMenuSection()
        Divider()
        let today = store.board.agendaTasks(through: 0)
        if today.isEmpty {
            Text(L("今天没有到期的任务"))
        } else {
            Text(L("今天和已过期（\(today.count)）"))
            ForEach(today.prefix(8)) { task in
                Button("  " + task.title) { open(task) }
            }
        }
        Divider()
        Button(L("打开 Best Planner")) { activateMain() }
        Toggle(L("登录时自动启动"), isOn: Binding(get: { launchAtLogin }, set: { on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Planner: login item change failed: \(error)")
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }))
        Divider()
        Button(L("退出")) { NSApp.terminate(nil) }
    }

    private func activateMain() {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { openWindow(id: "main") }
    }

    private func open(_ task: PlannerTask) {
        activateMain()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .openTaskRequested, object: task.id)
        }
    }
}

/// Focus status and controls in the menu bar menu.
private struct FocusMenuSection: View {
    @ObservedObject private var timer = FocusTimer.shared

    var body: some View {
        if timer.isRunning {
            Divider()
            Text("🍅 \(timer.taskTitle) · \(timer.label)\(timer.isPaused ? L("（已暂停）") : "")")
            Button(timer.isPaused ? L("继续专注") : L("暂停专注")) { timer.togglePause() }
            Button(L("结束专注")) { timer.stop() }
        }
    }
}
