import AppKit
import Combine
import SwiftUI

/// A small always-on-top countdown while focusing, for when the main window is closed or
/// another app is in front (inside the window the focus bar already shows the time).
/// Drag it anywhere; × hides it until the next focus session (or the menu bar brings it back).
@MainActor
final class FocusFloat {
    static let shared = FocusFloat()

    /// Opens the main window; set by a view that has SwiftUI's openWindow.
    static var openMainWindow: (() -> Void)?

    private var panel: NSPanel?
    private var hiddenByUser = false
    private var watching: [AnyCancellable] = []

    private init() {}

    /// Starts following the timer and the app's windows. Called once at launch.
    func start() {
        let timer = FocusTimer.shared
        timer.$taskID
            .removeDuplicates()
            .sink { [weak self] id in
                guard let self else { return }
                if id != nil { self.hiddenByUser = false }   // a new session shows it again
                DispatchQueue.main.async { self.update() }
            }
            .store(in: &watching)
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification,
        ]
        for name in names {
            center.publisher(for: name)
                .sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }
                .store(in: &watching)
        }
    }

    /// Shows it again after × (from the menu bar).
    func showAgain() {
        hiddenByUser = false
        update(force: true)
    }

    // Dragging (from the SwiftUI view): move by how far the mouse has gone.
    private var dragStart: (window: NSPoint, mouse: NSPoint)?

    func drag() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (panel.frame.origin, mouse) }
        guard let start = dragStart else { return }
        panel.setFrameOrigin(NSPoint(x: start.window.x + mouse.x - start.mouse.x, y: start.window.y + mouse.y - start.mouse.y))
    }

    func endDrag() {
        dragStart = nil
        panel?.saveFrame(usingName: "FocusFloat")
    }

    func hideByUser() {
        hiddenByUser = true
        panel?.orderOut(nil)
    }

    private var mainWindowShowing: Bool {
        NSApp.isActive && NSApp.windows.contains {
            $0 !== panel && $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain
        }
    }

    private func update(force: Bool = false) {
        let show = FocusTimer.shared.isRunning && !hiddenByUser && (force || !mainWindowShowing)
        if show {
            let p = panel ?? makePanel()
            panel = p
            p.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 250, height: 74),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        let host = DraggableHostingView(rootView: AnyView(FocusFloatView().appFontSize()))
        host.frame = p.contentRect(forFrameRect: p.frame)
        p.contentView = host
        if !p.setFrameUsingName("FocusFloat"), let screen = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: screen.maxX - 270, y: screen.maxY - 94))
        }
        p.setFrameAutosaveName("FocusFloat")
        return p
    }
}

/// Lets a drag anywhere on the floating timer (except its buttons) move it: SwiftUI's
/// hosting view otherwise keeps mouse-downs for itself, so the window wouldn't budge.
private final class DraggableHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// The floating countdown itself.
private struct FocusFloatView: View {
    @ObservedObject private var timer = FocusTimer.shared

    var body: some View {
        HStack(spacing: 10) {
            Text(timer.isResting ? "☕️" : "🍅").font(.system(size: 26))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(timer.label)
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.isPaused ? Color.secondary : timer.isResting ? Color.green : Color.primary)
                    if timer.isPaused {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.orange)
                            .help(L("已暂停"))
                    }
                }
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }) {
                        FocusFloat.openMainWindow?()
                    }
                } label: {
                    Text(timer.taskTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help(L("回到 Best Planner"))
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button { timer.togglePause() } label: { Image(systemName: timer.isPaused ? "play.fill" : "pause.fill") }
                        .help(timer.isPaused ? L("继续") : L("暂停"))
                    if timer.isResting {
                        Button { timer.skipRest() } label: { Image(systemName: "forward.end.fill") }
                            .help(L("跳过休息，开始下一轮"))
                    }
                    Button { timer.stop() } label: { Image(systemName: "stop.fill") }
                        .help(L("结束（已专注的分钟会记录下来）"))
                }
                Button { FocusFloat.shared.hideByUser() } label: {
                    Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                .help(L("收起浮窗（菜单栏的番茄菜单里可以再打开）"))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 250, height: 74)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.12)))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { _ in FocusFloat.shared.drag() }
            .onEnded { _ in FocusFloat.shared.endDrag() })
        .help(L("按住拖动可以移到任意位置"))
    }
}
