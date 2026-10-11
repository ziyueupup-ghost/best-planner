import AppKit
import SwiftUI
import UserNotifications

/// Pomodoro-style focus timer for one task. Finished (or stopped after ≥1 minute)
/// sessions are saved on the task. Shown as a bar in the window and in the menu bar.
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()
    static let durations = [15, 25, 45, 60]

    @Published private(set) var taskID: String?
    @Published private(set) var taskTitle = ""
    @Published private(set) var totalSeconds = 0
    @Published private(set) var remaining = 0
    @Published private(set) var isPaused = false
    private var startedAt = Date()
    private var tick: Timer?

    var isRunning: Bool { taskID != nil }
    var elapsedMinutes: Int { (totalSeconds - remaining) / 60 }
    var label: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }

    func start(_ task: PlannerTask, minutes: Int) {
        if isRunning { stop() }
        taskID = task.id
        taskTitle = task.title
        totalSeconds = minutes * 60
        remaining = totalSeconds
        isPaused = false
        startedAt = Date()
        schedule()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused { tick?.invalidate() } else { schedule() }
    }

    /// Ends early; keeps the minutes already focused (if at least one).
    func stop() {
        if let taskID, elapsedMinutes >= 1 {
            BoardStore.shared.addFocusSession(taskID, start: startedAt, minutes: elapsedMinutes)
        }
        reset()
    }

    private func finish() {
        guard let taskID else { return }
        BoardStore.shared.addFocusSession(taskID, start: startedAt, minutes: totalSeconds / 60)
        let content = UNMutableNotificationContent()
        content.title = L("🍅 专注完成")
        content.body = L("「\(taskTitle)」专注了 \(totalSeconds / 60) 分钟，休息一下吧。")
        content.sound = .default
        content.userInfo = ["taskID": taskID]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "focus-\(UUID().uuidString)", content: content, trigger: nil))
        NSSound.beep()
        reset()
    }

    private func reset() {
        tick?.invalidate()
        tick = nil
        taskID = nil
        taskTitle = ""
        remaining = 0
        totalSeconds = 0
        isPaused = false
    }

    private func schedule() {
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPaused else { return }
                self.remaining -= 1
                if self.remaining <= 0 { self.finish() }
            }
        }
    }
}

/// Bar at the bottom-left of the window while focusing.
struct FocusBar: View {
    @ObservedObject var timer = FocusTimer.shared

    var body: some View {
        if timer.isRunning {
            HStack(spacing: 10) {
                Text("🍅").scaledFont(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(timer.taskTitle).scaledFont(.callout, weight: .medium).lineLimit(1)
                    Text(timer.isPaused ? L("已暂停") : L("专注中")).scaledFont(.caption2).foregroundStyle(.secondary)
                }
                Text(timer.label)
                    .scaledFont(.title3, weight: .semibold, monospacedDigit: true)
                    .foregroundStyle(timer.isPaused ? .secondary : .primary)
                Button { timer.togglePause() } label: {
                    Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                }
                .help(timer.isPaused ? L("继续") : L("暂停"))
                Button { timer.stop() } label: { Image(systemName: "stop.fill") }
                    .help(L("结束（已专注的分钟会记录下来）"))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .frame(maxWidth: 360)
        }
    }
}

/// "开始专注" menu with the preset lengths.
struct FocusMenu: View {
    let task: PlannerTask

    var body: some View {
        Menu(L("开始专注 🍅")) {
            ForEach(FocusTimer.durations, id: \.self) { m in
                Button(L("\(m) 分钟")) { FocusTimer.shared.start(task, minutes: m) }
            }
        }
    }
}
