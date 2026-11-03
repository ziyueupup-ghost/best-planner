import AppKit
import SwiftUI
import UserNotifications

/// Pomodoro-style focus timer for one task: focus, then (optionally) break and focus
/// again for a number of rounds. Finished focus periods (or ones stopped after ≥1 minute)
/// are saved on the task; breaks aren't. Shown as a bar in the window and in the menu bar.
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()
    static let durations = [15, 25, 45, 60]

    enum Phase { case focus, rest }

    @Published private(set) var taskID: String?
    @Published private(set) var taskTitle = ""
    @Published private(set) var totalSeconds = 0
    @Published private(set) var remaining = 0
    @Published private(set) var isPaused = false
    @Published private(set) var phase = Phase.focus
    /// 1-based round and how many there are (1 = a single focus period).
    @Published private(set) var round = 1
    @Published private(set) var rounds = 1
    private var focusMinutes = 25
    private var restMinutes = 5
    private var startedAt = Date()
    private var tick: Timer?

    var isRunning: Bool { taskID != nil }
    var isResting: Bool { phase == .rest }

    private init() {
        // Quitting mid-session still records the minutes already focused.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                if FocusTimer.shared.isRunning {
                    FocusTimer.shared.stop()
                    BoardStore.shared.flush()
                }
            }
        }
    }
    var elapsedMinutes: Int { (totalSeconds - remaining) / 60 }
    var label: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }
    /// "专注 2/4", "休息", or just "专注中" for a single period.
    var phaseLabel: String {
        if isResting { return L("休息中") }
        return rounds > 1 ? L("专注 \(round)/\(rounds)") : L("专注中")
    }

    /// One focus period of `minutes`.
    func start(_ task: PlannerTask, minutes: Int) {
        start(task, focus: minutes, rest: 0, rounds: 1)
    }

    /// `rounds` focus periods of `focus` minutes with `rest`-minute breaks in between.
    func start(_ task: PlannerTask, focus: Int, rest: Int, rounds: Int) {
        if isRunning { stop() }
        FocusAlarm.shared.dismiss()
        taskID = task.id
        taskTitle = task.title
        focusMinutes = max(1, focus)
        restMinutes = max(1, rest)
        self.rounds = max(1, rounds)
        round = 1
        begin(.focus)
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused { tick?.invalidate() } else { schedule() }
    }

    /// Ends early; keeps the minutes already focused (if at least one).
    func stop() {
        if let taskID, phase == .focus, elapsedMinutes >= 1 {
            BoardStore.shared.addFocusSession(taskID, start: startedAt, minutes: elapsedMinutes)
        }
        reset()
    }

    /// During a break: start the next focus period now.
    func skipRest() {
        guard isResting else { return }
        round += 1
        begin(.focus)
    }

    private func begin(_ next: Phase) {
        phase = next
        totalSeconds = (next == .focus ? focusMinutes : restMinutes) * 60
        remaining = totalSeconds
        isPaused = false
        startedAt = Date()
        schedule()
    }

    private func finish() {
        guard let taskID else { return }
        if phase == .focus {
            BoardStore.shared.addFocusSession(taskID, start: startedAt, minutes: totalSeconds / 60)
            if round < rounds {
                notify(L("🍅 专注完成，休息一下"), L("「\(taskTitle)」第 \(round)/\(rounds) 轮完成，休息 \(restMinutes) 分钟。"))
                begin(.rest)
            } else {
                let total = focusMinutes * rounds
                notify(L("🍅 专注完成"), rounds > 1
                       ? L("「\(taskTitle)」完成 \(rounds) 轮，共专注 \(total) 分钟。")
                       : L("「\(taskTitle)」专注了 \(totalSeconds / 60) 分钟，休息一下吧。"))
                reset()
            }
        } else {
            round += 1
            notify(L("⏰ 休息结束"), L("开始第 \(round)/\(rounds) 轮专注：「\(taskTitle)」"))
            begin(.focus)
        }
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let taskID { content.userInfo = ["taskID": taskID] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "focus-\(UUID().uuidString)", content: content, trigger: nil))
        FocusAlarm.shared.ring(title: title, message: body)
    }

    private func reset() {
        tick?.invalidate()
        tick = nil
        taskID = nil
        taskTitle = ""
        remaining = 0
        totalSeconds = 0
        isPaused = false
        phase = .focus
        round = 1
        rounds = 1
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

/// Bar shown in the window while focusing: bottom-left at first, drag it anywhere in the
/// window (the spot is remembered, as a fraction of the window so resizing keeps it in view).
struct FocusBar: View {
    @ObservedObject var timer = FocusTimer.shared
    /// The space it can move in, and how much to keep clear at the bottom (the batch bar).
    var area: CGSize
    var bottomInset: CGFloat = 0

    /// Center of the bar as a fraction of `area`; negative = the default bottom-left spot.
    @AppStorage("focusBarX") private var fractionX = -1.0
    @AppStorage("focusBarY") private var fractionY = -1.0
    @State private var size = CGSize(width: 300, height: 44)
    @State private var dragStart: CGPoint?

    private let margin: CGFloat = 14

    private var center: CGPoint {
        let point = fractionX < 0 || fractionY < 0
            ? CGPoint(x: margin + size.width / 2, y: area.height - margin - bottomInset - size.height / 2)
            : CGPoint(x: fractionX * area.width, y: fractionY * area.height)
        return clamped(point)
    }

    /// Keeps the whole bar inside the window.
    private func clamped(_ p: CGPoint) -> CGPoint {
        let halfW = size.width / 2, halfH = size.height / 2, edge: CGFloat = 4
        return CGPoint(x: min(max(p.x, halfW + edge), max(halfW + edge, area.width - halfW - edge)),
                       y: min(max(p.y, halfH + edge), max(halfH + edge, area.height - halfH - edge)))
    }

    var body: some View {
        if timer.isRunning && area.width > 0 {
            bar
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { size = geo.size }
                        .onChange(of: geo.size) { _, new in size = new }
                })
                .position(center)
                .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .local)
                    .onChanged { value in
                        let start = dragStart ?? center
                        if dragStart == nil { dragStart = start }
                        let p = clamped(CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height))
                        fractionX = p.x / area.width
                        fractionY = p.y / area.height
                    }
                    .onEnded { _ in dragStart = nil })
                .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
                .contextMenu {
                    Button(L("放回左下角")) { fractionX = -1; fractionY = -1 }
                        .disabled(fractionX < 0)
                }
                .help(L("按住拖动可以移到任意位置"))
        }
    }

    private var bar: some View {
            HStack(spacing: 10) {
                Text(timer.isResting ? "☕️" : "🍅").scaledFont(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(timer.taskTitle).scaledFont(.callout, weight: .medium).lineLimit(1)
                    Text(timer.isPaused ? L("已暂停") : timer.phaseLabel).scaledFont(.caption2).foregroundStyle(.secondary)
                }
                Text(timer.label)
                    .scaledFont(.title3, weight: .semibold, monospacedDigit: true)
                    .foregroundStyle(timer.isPaused ? Color.secondary : timer.isResting ? Color.green : Color.primary)
                Button { timer.togglePause() } label: {
                    Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                }
                .help(timer.isPaused ? L("继续") : L("暂停"))
                if timer.isResting {
                    Button { timer.skipRest() } label: { Image(systemName: "forward.end.fill") }
                        .help(L("跳过休息，开始下一轮"))
                }
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
            .fixedSize()
    }
}

/// "开始专注" menu: preset lengths, the user's own length, and focus/break cycles.
struct FocusMenu: View {
    let task: PlannerTask
    /// In a right-click menu there's nowhere to show the settings popover; those are
    /// changed from the task editor instead.
    var inContextMenu = false
    @AppStorage("focusMinutes") private var focusMinutes = 25
    @AppStorage("focusRestMinutes") private var restMinutes = 5
    @AppStorage("focusRounds") private var rounds = 4
    @State private var showSettings = false

    var body: some View {
        Menu(L("开始专注 🍅")) {
            Section(L("专注一次")) {
                ForEach(FocusTimer.durations, id: \.self) { m in
                    Button(L("\(m) 分钟")) { FocusTimer.shared.start(task, minutes: m) }
                }
                if !FocusTimer.durations.contains(focusMinutes) {
                    Button(L("\(focusMinutes) 分钟")) { FocusTimer.shared.start(task, minutes: focusMinutes) }
                }
            }
            Section(L("番茄循环")) {
                Button(L("专注 \(focusMinutes) 分钟 · 休息 \(restMinutes) 分钟 × \(rounds) 轮")) {
                    FocusTimer.shared.start(task, focus: focusMinutes, rest: restMinutes, rounds: rounds)
                }
            }
            if !inContextMenu {
                Divider()
                Button(L("设置时长和循环…")) { showSettings = true }
            }
        }
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            FocusSettings(task: task, focusMinutes: $focusMinutes, restMinutes: $restMinutes, rounds: $rounds) {
                showSettings = false
            }
        }
    }
}

/// The user's own focus length, break length and number of rounds.
private struct FocusSettings: View {
    let task: PlannerTask
    @Binding var focusMinutes: Int
    @Binding var restMinutes: Int
    @Binding var rounds: Int
    let done: () -> Void
    @AppStorage(FocusAlarm.enabledKey) private var alarmOn = true
    @AppStorage(FocusAlarm.soundKey) private var alarmSound = "Glass"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("专注设置")).scaledFont(.headline)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    Text(L("专注"))
                    NumberField(value: $focusMinutes, range: 1...180)
                    Text(L("分钟"))
                }
                GridRow {
                    Text(L("休息"))
                    NumberField(value: $restMinutes, range: 1...60)
                    Text(L("分钟"))
                }
                GridRow {
                    Text(L("循环"))
                    NumberField(value: $rounds, range: 1...12)
                    Text(L("轮"))
                }
            }
            Divider()
            Toggle(L("结束时响闹钟"), isOn: $alarmOn)
            if alarmOn {
                Picker(L("铃声"), selection: $alarmSound) {
                    ForEach(FocusAlarm.sounds, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: alarmSound) { _, name in FocusAlarm.preview(name) }
            }
            Text(rounds > 1
                 ? L("专注 \(focusMinutes) 分钟 → 休息 \(restMinutes) 分钟 → … 共 \(rounds) 轮，总共专注 \(focusMinutes * rounds) 分钟。")
                 : L("专注一次 \(focusMinutes) 分钟。"))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("开始")) {
                    FocusTimer.shared.start(task, focus: focusMinutes, rest: restMinutes, rounds: rounds)
                    done()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
