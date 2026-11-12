import Charts
import SwiftUI

/// 工作台: one screen packed with charts about the user's own tasks (white cards on the
/// window background). Each tag is a project.
/// - left: projects as a rose chart (petal length = tasks), the headline numbers, and
///   each project's progress as bars;
/// - middle: today's numbers, two rings (today / this week), a water gauge for overall
///   progress, and tasks finished vs created over 30 days;
/// - right: a radar of how things are going, a table of the projects, and focus
///   minutes over 14 days;
/// - bottom: what's due in the next two weeks (and what's overdue).
struct DashboardView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.fontScale) private var fontScale
    let onEdit: (PlannerTask) -> Void
    /// Shows the board with only this tag's tasks.
    let onOpenTag: (String) -> Void
    /// The number whose tasks are listed in a popover (its title).
    @State private var shownList: String?

    private let cal = Calendar.current
    private var board: Board { store.board }
    private var open: [PlannerTask] { board.tasks.filter { !board.isDone($0) } }
    private var today: Date { cal.startOfDay(for: Date()) }

    var body: some View {
        GeometryReader { geo in
            // Three columns on a wide window, two on a medium one, one when narrow.
            let w = geo.size.width - 36
            let columns = w >= 1100 * fontScale ? 3 : w >= 700 * fontScale ? 2 : 1
            ScrollView {
                VStack(spacing: 14) {
                    titleBar(compact: columns == 1)
                    switch columns {
                    case 3:
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 14) { roseAndNumbers; projectBars }
                                .frame(width: (w - 28) * 0.27)
                            VStack(spacing: 14) { todayNumbers; gauges; dailyChart }
                                .frame(width: (w - 28) * 0.43)
                            VStack(spacing: 14) { radar; ranking; focusChart }
                                .frame(width: (w - 28) * 0.30)
                        }
                    case 2:
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 14) { roseAndNumbers; projectBars; radar }
                                .frame(width: (w - 14) * 0.42)
                            VStack(spacing: 14) { todayNumbers; gauges; dailyChart; ranking; focusChart }
                                .frame(width: (w - 14) * 0.58)
                        }
                    default:
                        VStack(spacing: 14) {
                            todayNumbers; gauges; roseAndNumbers; projectBars; dailyChart; radar; ranking; focusChart
                        }
                    }
                    upcomingStrip
                }
                .padding(18)
            }
        }
        .background(Screen.background)
    }

    // MARK: Title

    @ViewBuilder
    private func titleBar(compact: Bool) -> some View {
        if compact {
            VStack(spacing: 2) {
                Text(L("工作台")).font(.system(size: 22 * fontScale, weight: .bold))
                Text(Date().formatted(.dateTime.month().day().weekday(.wide))).scaledFont(.callout).foregroundStyle(.secondary)
            }
        } else {
            wideTitleBar
        }
    }

    private var wideTitleBar: some View {
        ZStack {
            HStack {
                Text(L("我的项目")).foregroundStyle(.secondary)
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(ctx.date.formatted(Date.FormatStyle.dateTime.year().month().day().weekday(.wide).hour().minute().locale(.clock24)))
                        .monospacedDigit()
                        .foregroundStyle(Screen.text.opacity(0.85))
                }
            }
            .scaledFont(.callout)
            Text(L("工作台"))
                .font(.system(size: 22 * fontScale, weight: .bold))
        }
        .padding(.horizontal, 6)
        .frame(height: 50 * fontScale)
    }

    // MARK: Data

    private struct Project: Identifiable {
        let id: String
        let tag: Tag?
        let tasks: [PlannerTask]
        let done: Int
        var name: String { tag.map { $0.icon.isEmpty ? $0.name : "\($0.icon) \($0.name)" } ?? L("无标签") }
        var color: Color { tag.map { Color(hex: $0.colorHex) } ?? .gray }
        var fraction: Double { tasks.isEmpty ? 0 : Double(done) / Double(tasks.count) }
    }

    /// One project per tag that has tasks, plus untagged tasks when there are any.
    private var projects: [Project] {
        var list = board.tags.compactMap { tag -> Project? in
            let tasks = board.tasks.filter { $0.tagIDs.contains(tag.id) }
            return tasks.isEmpty ? nil : Project(id: tag.id, tag: tag, tasks: tasks, done: tasks.filter { board.isDone($0) }.count)
        }
        let untagged = board.tasks.filter { t in !t.tagIDs.contains { id in board.tags.contains { $0.id == id } } }
        if !untagged.isEmpty {
            list.append(Project(id: "none", tag: nil, tasks: untagged, done: untagged.filter { board.isDone($0) }.count))
        }
        return list
    }

    private func completed(on day: Date) -> Int {
        board.tasks.filter { t in board.isDone(t) && t.completedAt.map { cal.isDate($0, inSameDayAs: day) } == true }.count
    }

    private func created(on day: Date) -> Int {
        (board.tasks + board.trash).filter { cal.isDate($0.createdAt, inSameDayAs: day) }.count
    }

    /// Finished tasks, latest first.
    private var doneTasks: [PlannerTask] {
        board.tasks.filter { board.isDone($0) }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var overdueItems: [(PlannerTask, String)] {
        open.compactMap { t in t.dates.first { board.isOverdue($0, of: t) }.map { (t, L("截止 \($0.label)")) } }
    }

    private func doneItems(since start: Date) -> [(PlannerTask, String)] {
        doneTasks.filter { ($0.completedAt ?? .distantPast) >= start }.map { ($0, $0.completedAt!.dayLabel) }
    }

    private var weekStart: Date { cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today }

    private func doneSince(_ start: Date) -> Int {
        board.tasks.filter { t in board.isDone(t) && (t.completedAt ?? .distantPast) >= start }.count
    }

    // MARK: Left

    private var roseAndNumbers: some View {
        let list = projects
        let maxCount = Double(list.map(\.tasks.count).max() ?? 1)
        let total = board.tasks.count
        let done = board.tasks.filter { board.isDone($0) }.count
        let overdue = open.filter { t in t.dates.contains { board.isOverdue($0, of: t) } }.count
        return ScreenPanel(title: L("项目分布"), symbol: "chart.pie") {
            if list.isEmpty {
                emptyText(L("还没有任务。"))
            } else {
                // Nightingale rose: one equal slice per project, its length = how many tasks.
                Chart(list) { p in
                    SectorMark(angle: .value("", 1),
                               innerRadius: .ratio(0.18),
                               outerRadius: .ratio(0.35 + 0.65 * Double(p.tasks.count) / maxCount),
                               angularInset: 1.5)
                        .foregroundStyle(p.color)
                        .cornerRadius(3)
                }
                .chartLegend(.hidden)
                .frame(height: 170 * fontScale)
                legend(list.map { ($0.name, $0.color, "\($0.tasks.count)") })
            }
            HStack(spacing: 10) {
                bigNumber(L("全部任务"), "\(total)", .primary,
                          board.tasks.map { ($0, board.column($0.columnID)?.name ?? "") })
                bigNumber(L("已完成"), "\(done)", .primary,
                          doneTasks.map { ($0, $0.completedAt?.dayLabel ?? "") })
            }
            HStack(spacing: 10) {
                let doing = open.filter { board.isStarted($0) }
                bigNumber(L("进行中"), "\(doing.count)", .primary, doing.map { ($0, board.column($0.columnID)?.name ?? "") })
                bigNumber(L("已逾期"), "\(overdue)", overdue > 0 ? Screen.red : .primary, overdueItems)
            }
        }
    }

    private var projectBars: some View {
        let list = projects.sorted { $0.fraction > $1.fraction }
        return ScreenPanel(title: L("项目进度榜"), symbol: "list.number") {
            if list.isEmpty { emptyText(L("还没有任务。")) }
            ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                Button { if let tag = p.tag { onOpenTag(tag.id) } } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("No.\(i + 1)").foregroundStyle(.secondary).monospacedDigit()
                            Text(p.name).foregroundStyle(Screen.text).lineLimit(1)
                            Spacer()
                            Text("\(Int((p.fraction * 100).rounded()))%  \(p.done)/\(p.tasks.count)")
                                .foregroundStyle(Screen.text.opacity(0.75)).monospacedDigit()
                        }
                        .scaledFont(.caption)
                        GlowBar(fraction: p.fraction, color: p.color)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(p.tag == nil ? "" : L("看这个项目的看板"))
            }
        }
    }

    // MARK: Middle

    private var todayNumbers: some View {
        let dueToday = open.compactMap { t in t.dates.first { cal.isDateInToday($0.date) }.map { (t, "\($0.kind.title) \($0.label)") } }
        let monthStart = cal.dateInterval(of: .month, for: today)?.start ?? today
        let focused = board.tasks.compactMap { t -> (PlannerTask, Int)? in
            let m = t.focusSessions.filter { $0.start >= weekStart }.reduce(0) { $0 + $1.minutes }
            return m > 0 ? (t, m) : nil
        }.sorted { $0.1 > $1.1 }
        let waiting = open.filter { !board.waitingOn($0).isEmpty }
        let stale = open.filter { board.staleDays($0) != nil }
        let stuck = waiting.map { ($0, board.describe(board.waitingOn($0))) }
            + stale.filter { t in !waiting.contains { $0.id == t.id } }.map { ($0, L("在「\(board.column($0.columnID)?.name ?? "")」待了 \(board.staleDays($0) ?? 0) 天")) }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 120 * fontScale), spacing: 10)], spacing: 10) {
            statBox(L("今天要做"), "\(dueToday.count)", dueToday)
            statBox(L("今天完成"), "\(completed(on: today))", doneItems(since: today))
            statBox(L("本周完成"), "\(doneSince(weekStart))", doneItems(since: weekStart))
            statBox(L("本月完成"), "\(doneSince(monthStart))", doneItems(since: monthStart))
            statBox(L("本周专注（分钟）"), "\(focused.reduce(0) { $0 + $1.1 })", focused.map { ($0.0, L("\($0.1) 分钟")) })
            statBox(L("在等 / 停留太久"), "\(waiting.count) / \(stale.count)", stuck)
        }
    }

    private var gauges: some View {
        let dueToday = board.tasks.filter { t in t.dates.contains { cal.isDateInToday($0.date) } }
        let todayRate = dueToday.isEmpty ? 0 : Double(dueToday.filter { board.isDone($0) }.count) / Double(dueToday.count)
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)!
        let thisWeek = board.tasks.filter { t in t.dates.contains { $0.date >= weekStart && $0.date < weekEnd } }
        let weekRate = thisWeek.isEmpty ? 0 : Double(thisWeek.filter { board.isDone($0) }.count) / Double(thisWeek.count)
        let total = board.tasks.count
        let overall = total == 0 ? 0 : Double(board.tasks.filter { board.isDone($0) }.count) / Double(total)
        let status: (PlannerTask) -> String = { board.isDone($0) ? L("已完成") : L("还没完成") }
        return HStack(spacing: 14) {
            listButton(L("今天的任务完成率"), dueToday.map { ($0, status($0)) }) {
                VStack(spacing: 6) {
                    GlowRing(fraction: todayRate, color: Screen.cyan)
                        .frame(maxWidth: 92 * fontScale, maxHeight: 92 * fontScale)
                        .aspectRatio(1, contentMode: .fit)
                    Text(L("今天的任务完成率")).scaledFont(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            listButton(L("本周的任务完成率"), thisWeek.map { ($0, status($0)) }) {
                VStack(spacing: 6) {
                    GlowRing(fraction: weekRate, color: Screen.cyan)
                        .frame(maxWidth: 92 * fontScale, maxHeight: 92 * fontScale)
                        .aspectRatio(1, contentMode: .fit)
                    Text(L("本周的任务完成率")).scaledFont(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                WaterGauge(fraction: overall)
                    .frame(maxWidth: 150 * fontScale)
                    .frame(height: 80 * fontScale)
                Text(L("总体进度")).scaledFont(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(PanelBackground())
    }

    private struct DayCount: Identifiable {
        let day: Date
        let value: Int
        var id: Date { day }
    }

    private var dailyChart: some View {
        let days = (0..<30).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
        let done = days.map { DayCount(day: $0, value: completed(on: $0)) }
        let made = days.map { DayCount(day: $0, value: created(on: $0)) }
        return ScreenPanel(title: L("最近 30 天：完成和新建的任务"), symbol: "chart.bar") {
            // Finished (blue) and created (grey) side by side for each day.
            Chart {
                ForEach(done) { d in
                    BarMark(x: .value(L("日期"), d.day, unit: .day), y: .value(L("任务"), d.value), width: .ratio(0.8))
                        .foregroundStyle(Screen.cyan)
                        .position(by: .value("", L("完成")))
                        .cornerRadius(2)
                }
                ForEach(made) { d in
                    BarMark(x: .value(L("日期"), d.day, unit: .day), y: .value(L("任务"), d.value), width: .ratio(0.8))
                        .foregroundStyle(Screen.pink)
                        .position(by: .value("", L("新建")))
                        .cornerRadius(2)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day()).foregroundStyle(Color.gray)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel().foregroundStyle(Color.gray)
                }
            }
            .frame(height: 210 * fontScale)
            legend([(L("完成"), Screen.cyan, ""), (L("新建"), Screen.pink, "")])
        }
    }

    // MARK: Right

    /// How things are going, 0–100% on six axes.
    private var radar: some View {
        let total = max(board.tasks.count, 1), openCount = max(open.count, 1)
        let overdue = open.filter { t in t.dates.contains { board.isOverdue($0, of: t) } }.count
        let waiting = open.filter { !board.waitingOn($0).isEmpty }.count
        let stale = open.filter { board.staleDays($0) != nil }.count
        let last14 = (0..<14).map { cal.date(byAdding: .day, value: -$0, to: today)! }
        let activeDays = last14.filter { completed(on: $0) > 0 }.count
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today)!
        let focus7 = board.tasks.flatMap(\.focusSessions).filter { $0.start >= weekAgo }.reduce(0) { $0 + $1.minutes }
        let values: [(String, Double)] = [
            (L("完成率"), Double(board.tasks.filter { board.isDone($0) }.count) / Double(total)),
            (L("按时"), 1 - Double(overdue) / Double(openCount)),
            (L("活跃"), Double(activeDays) / 14),
            (L("专注"), min(1, Double(focus7) / (7 * 60))),
            (L("顺畅"), 1 - Double(waiting) / Double(openCount)),
            (L("不拖延"), 1 - Double(stale) / Double(openCount)),
        ]
        return ScreenPanel(title: L("工作状态雷达"), symbol: "dot.radiowaves.left.and.right") {
            RadarChart(values: values, color: Screen.cyan)
                .frame(height: 200 * fontScale)
                .help(values.map { "\($0.0) \(Int(($0.1 * 100).rounded()))%" }.joined(separator: "\n"))
        }
    }

    private var ranking: some View {
        let lastWeek = cal.date(byAdding: .day, value: -7, to: weekStart)!
        let rows = projects.sorted { $0.tasks.count > $1.tasks.count }
        return ScreenPanel(title: L("项目一览"), symbol: "tablecells") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
                GridRow {
                    Text("#"); Text(L("项目")); Text(L("任务")); Text(L("完成率")); Text(L("本周"))
                }
                .foregroundStyle(.secondary)
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, p in
                    let week = p.tasks.filter { t in board.isDone(t) && (t.completedAt ?? .distantPast) >= weekStart }.count
                    let before = p.tasks.filter { t in board.isDone(t) && (t.completedAt.map { $0 >= lastWeek && $0 < weekStart } ?? false) }.count
                    GridRow {
                        Text("\(i + 1)").foregroundStyle(Screen.text.opacity(0.6))
                        Text(p.name).foregroundStyle(Screen.text).lineLimit(1)
                        Text("\(p.tasks.count)").foregroundStyle(Screen.text)
                        Text("\(Int((p.fraction * 100).rounded()))%").foregroundStyle(Screen.text)
                        Text(week >= before ? "↑\(week)" : "↓\(week)")
                            .foregroundStyle(week >= before ? Screen.green : Screen.red)
                            .help(L("本周完成 \(week) 个，上周 \(before) 个"))
                    }
                    .onTapGesture { if let tag = p.tag { onOpenTag(tag.id) } }
                }
            }
            .scaledFont(.caption)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var focusChart: some View {
        let sessions = board.tasks.flatMap(\.focusSessions)
        let data = (0..<14).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }.map { d in
            DayCount(day: d, value: sessions.filter { cal.isDate($0.start, inSameDayAs: d) }.reduce(0) { $0 + $1.minutes })
        }
        let average = Double(data.reduce(0) { $0 + $1.value }) / Double(max(data.count, 1))
        return ScreenPanel(title: L("最近 14 天专注（分钟）"), symbol: "waveform.path.ecg") {
            Chart {
                ForEach(data) { d in
                    AreaMark(x: .value(L("日期"), d.day, unit: .day), y: .value(L("分钟"), d.value))
                        .foregroundStyle(LinearGradient(colors: [Screen.cyan.opacity(0.3), Screen.cyan.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value(L("日期"), d.day, unit: .day), y: .value(L("分钟"), d.value))
                        .foregroundStyle(Screen.cyan)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value(L("日期"), d.day, unit: .day), y: .value(L("分钟"), d.value))
                        .foregroundStyle(Screen.cyan)
                        .symbolSize(16)
                }
                RuleMark(y: .value(L("平均"), average))
                    .foregroundStyle(Screen.amber)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(L("平均 \(Int(average.rounded()))")).scaledFont(.caption2).foregroundStyle(Screen.amber)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day()).foregroundStyle(Color.gray)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel().foregroundStyle(Color.gray)
                }
            }
            .frame(height: 160 * fontScale)
        }
    }

    // MARK: Bottom

    /// What's due in the next two weeks (and what's overdue), as a strip of small cards.
    private var upcomingStrip: some View {
        let end = cal.date(byAdding: .day, value: 14, to: today)!
        let due = open.compactMap { t -> (PlannerTask, TaskDate)? in
            guard let d = t.dates.filter({ $0.kind != .reminder && $0.dueDate < end && ($0.dueDate >= today || board.isOverdue($0, of: t)) })
                .min(by: { $0.date < $1.date }) else { return nil }
            return (t, d)
        }
        .sorted { $0.1.date < $1.1.date }
        return ScreenPanel(title: L("接下来两周（含已逾期）"), symbol: "calendar") {
            if due.isEmpty { emptyText(L("接下来两周没有安排。")) }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(due.prefix(20), id: \.0.id) { t, d in
                        let late = board.isOverdue(d, of: t)
                        let color = board.tags(for: t).first.map { Color(hex: $0.colorHex) } ?? Screen.cyan
                        Button { onEdit(t) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cal.isDateInToday(d.date) ? L("今天") : d.label)
                                    .font(.system(size: 18 * fontScale, weight: .semibold, design: .rounded))
                                    .foregroundStyle(late ? Screen.red : .primary)
                                Text(t.title).scaledFont(.caption).foregroundStyle(Screen.text).lineLimit(1)
                                Text(late ? L("已逾期") : d.kind.title).scaledFont(.caption2).foregroundStyle(Screen.text.opacity(0.6))
                            }
                            .padding(10)
                            .frame(width: 130 * fontScale, alignment: .leading)
                            .background(Screen.panel, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(late ? Screen.red.opacity(0.6) : Color.primary.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .help(L("打开这个任务"))
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func emptyText(_ s: String) -> some View {
        Text(s).scaledFont(.caption).foregroundStyle(Screen.text.opacity(0.6))
    }

    private func legend(_ items: [(String, Color, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90 * fontScale), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(items, id: \.0) { name, color, value in
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(name).foregroundStyle(Screen.text.opacity(0.85)).lineLimit(1)
                    if !value.isEmpty { Text(value).foregroundStyle(Screen.text.opacity(0.55)) }
                }
                .scaledFont(.caption2)
            }
        }
    }

    private func bigNumber(_ title: String, _ value: String, _ color: Color, _ items: [(PlannerTask, String)]) -> some View {
        listButton(title, items) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 26 * fontScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                Text(title).scaledFont(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statBox(_ title: String, _ value: String, _ items: [(PlannerTask, String)]) -> some View {
        listButton(title, items) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).scaledFont(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(value)
                    .font(.system(size: 24 * fontScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(PanelBackground())
        }
    }

    /// Makes `label` clickable: it lists the tasks behind the number in a popover.
    private func listButton<Label: View>(_ title: String, _ items: [(PlannerTask, String)], @ViewBuilder label: () -> Label) -> some View {
        Button { shownList = title } label: { label().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .help(L("点一下看是哪几个任务"))
            .popover(isPresented: Binding(get: { shownList == title }, set: { if !$0 { shownList = nil } })) {
                TaskListPopover(title: title, items: items) { task in
                    shownList = nil
                    onEdit(task)
                }
                .environmentObject(store)
            }
    }
}

// MARK: - Look

/// One accent (blue) for everything "done"; grey for secondary series; red and orange only
/// for overdue / stuck. Projects keep their tag colours.
private enum Screen {
    static let cyan = Color(hex: "#2A78D6")      // the accent
    static let blue = Color(hex: "#7FB0EA")
    static let pink = Color(hex: "#A3ACB9")      // secondary series (grey)
    static let amber = Color(hex: "#EB6834")
    static let green = Color(hex: "#1BAF7A")
    static let red = Color(hex: "#E34948")
    static let text = Color.primary
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let background = Color(nsColor: .windowBackgroundColor)
}

/// A panel: a white card with a hairline border.
private struct PanelBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Screen.panel)
            RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ScreenPanel<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text(title).foregroundStyle(.primary)
            }
            .scaledFont(.callout, weight: .semibold)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(PanelBackground())
    }
}

/// A thin glowing progress bar.
private struct GlowBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 7)
    }
}

/// A ring gauge with a glow and the percentage in the middle.
private struct GlowRing: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.07), lineWidth: s * 0.09)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: s * 0.09, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: s * 0.24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A "water level" gauge: moving waves filled up to `fraction`.
private struct WaterGauge: View {
    let fraction: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10)
                g.fill(shape, with: .color(Color.primary.opacity(0.04)))
                g.clip(to: shape)
                let level = size.height * (1 - fraction)
                for (i, alpha) in [(0, 0.45), (1, 0.85)] {
                    var wave = Path()
                    wave.move(to: CGPoint(x: 0, y: size.height))
                    for x in stride(from: 0, through: size.width, by: 2) {
                        let y = level + sin(x / size.width * 2 * .pi * 1.4 + t * (1.6 + Double(i) * 0.6) + Double(i)) * 5
                        wave.addLine(to: CGPoint(x: x, y: y))
                    }
                    wave.addLine(to: CGPoint(x: size.width, y: size.height))
                    wave.closeSubpath()
                    g.fill(wave, with: .color(Screen.cyan.opacity(alpha * 0.55)))
                }
                g.draw(Text("\(Int((fraction * 100).rounded()))%").font(.system(size: size.height * 0.3, weight: .bold, design: .rounded))
                    .foregroundColor(.primary), at: CGPoint(x: size.width / 2, y: size.height / 2))
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

/// A radar (spider) chart: values 0…1 on evenly spread axes.
private struct RadarChart: View {
    let values: [(String, Double)]
    let color: Color

    var body: some View {
        Canvas { g, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 26
            let n = values.count
            func point(_ i: Int, _ r: Double) -> CGPoint {
                let a = Double(i) / Double(n) * 2 * .pi - .pi / 2
                return CGPoint(x: center.x + cos(a) * radius * r, y: center.y + sin(a) * radius * r)
            }
            for level in 1...4 {
                var ring = Path()
                for i in 0..<n {
                    if i == 0 { ring.move(to: point(i, Double(level) / 4)) } else { ring.addLine(to: point(i, Double(level) / 4)) }
                }
                ring.closeSubpath()
                g.stroke(ring, with: .color(Color.primary.opacity(0.1)), lineWidth: 1)
            }
            for i in 0..<n {
                var axis = Path()
                axis.move(to: center)
                axis.addLine(to: point(i, 1))
                g.stroke(axis, with: .color(Color.primary.opacity(0.1)), lineWidth: 1)
                g.draw(Text(values[i].0).font(.caption2).foregroundColor(Screen.text.opacity(0.85)), at: point(i, 1.2))
            }
            var shape = Path()
            for (i, v) in values.enumerated() {
                let p = point(i, max(0.04, v.1))
                if i == 0 { shape.move(to: p) } else { shape.addLine(to: p) }
            }
            shape.closeSubpath()
            g.fill(shape, with: .radialGradient(Gradient(colors: [color.opacity(0.2), color.opacity(0.6)]),
                                                center: center, startRadius: 0, endRadius: radius))
            g.stroke(shape, with: .color(color), lineWidth: 1.5)
            for (i, v) in values.enumerated() {
                let p = point(i, max(0.04, v.1))
                g.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(color))
            }
        }
    }
}

/// The tasks behind a number on the dashboard; click one to open it.
private struct TaskListPopover: View {
    @EnvironmentObject private var store: BoardStore
    let title: String
    let items: [(PlannerTask, String)]
    let onOpen: (PlannerTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title) · \(items.count)").font(.headline)
            if items.isEmpty {
                Text(L("没有任务。")).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(items.prefix(200).enumerated()), id: \.offset) { _, item in
                            let (task, detail) = item
                            Button { onOpen(task) } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(store.board.tags(for: task).first.map { Color(hex: $0.colorHex) } ?? Color.gray.opacity(0.5))
                                        .frame(width: 7, height: 7)
                                    Text(task.title.isEmpty ? L("（无标题）") : task.title).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(detail).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(L("打开这个任务"))
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}
