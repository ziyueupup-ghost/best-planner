import SwiftUI
import WidgetKit

struct PlannerEntry: TimelineEntry {
    let date: Date
    let board: Board
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PlannerEntry {
        PlannerEntry(date: Date(), board: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlannerEntry) -> Void) {
        let board = PlannerStorage.load()
        completion(PlannerEntry(date: Date(), board: board.tasks.isEmpty && context.isPreview ? Self.sample : board))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlannerEntry>) -> Void) {
        let entry = PlannerEntry(date: Date(), board: PlannerStorage.load())
        // The app asks for a reload on every change; also refresh every 15 min (and just after
        // midnight, so overdue deadlines turn red) in case that request is dropped.
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
        let next = min(midnight.addingTimeInterval(60), Date().addingTimeInterval(15 * 60))
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    static var sample: Board {
        var b = Board.empty
        var t1 = PlannerTask(title: "写周报", columnID: "todo")
        t1.priorityID = "urgent"
        t1.tagIDs = [b.tags[0].id]
        t1.dates = [TaskDate(kind: .deadline, date: Date().addingTimeInterval(86_400))]
        var t2 = PlannerTask(title: "设计新页面", columnID: "doing")
        t2.subtasks = [Subtask(title: "草图", isDone: true), Subtask(title: "高保真")]
        b.tasks = [t1, t2, PlannerTask(title: "回复邮件", columnID: "todo"), PlannerTask(title: "整理笔记", columnID: "done")]
        return b
    }
}

/// One line in the widget: a task, one of its subtasks, or "N more".
enum WidgetRow: Identifiable {
    case task(PlannerTask)
    case subtask(PlannerTask, Subtask)
    case more(String, Int)

    var id: String {
        switch self {
        case .task(let t): "t-\(t.id)"
        case .subtask(let t, let s): "s-\(t.id)-\(s.id)"
        case .more(let key, _): "m-\(key)"
        }
    }
}

struct PlannerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlannerEntry

    private var board: Board { entry.board }
    private var activeColumns: [BoardColumn] { board.columns.filter { !$0.isDone } }
    /// Ticking a task needs somewhere to move it.
    private var canCompleteTasks: Bool { board.columns.contains { $0.isDone } }

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemLarge: large
        default: medium
        }
    }

    // MARK: Small — progress + what's next

    private var small: some View {
        let total = board.tasks.count
        let done = board.tasks.filter { board.isDone($0) }.count
        let next = activeColumns.reversed().flatMap { board.tasks(in: $0.id) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Best Planner").font(.headline)
                Spacer()
                Text("\(done)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(board.columns.first { $0.isDone }?.color ?? .green)
                .padding(.bottom, 2)
            if next.isEmpty {
                Spacer(minLength: 0)
                Text("全部完成 🎉").font(.caption).foregroundStyle(.secondary)
            } else {
                rowList(rows(next, budget: 4, key: "small"), showMeta: false)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Medium — first two active columns

    private var medium: some View {
        let cols = Array((activeColumns.isEmpty ? board.columns : activeColumns).prefix(2))
        return HStack(alignment: .top, spacing: 12) {
            ForEach(Array(cols.enumerated()), id: \.element.id) { i, c in
                if i > 0 { Divider() }
                column(c, budget: 5)
            }
        }
    }

    // MARK: Large — all columns stacked, subtasks included

    private var large: some View {
        let cols = Array(board.columns.prefix(4))
        let active = max(cols.filter { !$0.isDone }.count, 1)
        let budget = max(3, 12 / active)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Best Planner").font(.headline)
                Spacer()
                Text(entry.date, format: .dateTime.month().day().weekday())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(cols.enumerated()), id: \.element.id) { i, c in
                if i > 0 { Divider() }
                column(c, budget: c.isDone ? 2 : budget)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Pieces

    private func column(_ c: BoardColumn, budget: Int) -> some View {
        let tasks = board.tasks(in: c.id)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if c.icon.isEmpty {
                    Circle().fill(c.color).frame(width: 8, height: 8)
                } else {
                    Text(c.icon).font(.caption)
                }
                Text(c.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(tasks.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if tasks.isEmpty {
                Text("暂无任务").font(.caption).foregroundStyle(.tertiary)
            }
            rowList(rows(tasks, budget: budget, key: c.id), showMeta: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Tasks followed by their subtasks (open tasks only), cut off at `budget` lines.
    private func rows(_ tasks: [PlannerTask], budget: Int, key: String) -> [WidgetRow] {
        var out: [WidgetRow] = []
        var shownTasks = 0
        for t in tasks {
            if out.count >= budget { break }
            out.append(.task(t))
            shownTasks += 1
            guard !board.isDone(t) else { continue }
            for s in t.subtasks where out.count < budget {
                out.append(.subtask(t, s))
            }
        }
        if tasks.count > shownTasks { out.append(.more(key, tasks.count - shownTasks)) }
        return out
    }

    private func rowList(_ rows: [WidgetRow], showMeta: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(rows) { row in
                switch row {
                case .task(let t): taskRow(t, showMeta: showMeta)
                case .subtask(let t, let s): subtaskRow(t, s)
                case .more(_, let n):
                    Text("还有 \(n) 项…").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func taskRow(_ task: PlannerTask, showMeta: Bool) -> some View {
        let done = board.isDone(task)
        let p = task.subtaskProgress
        return HStack(spacing: 4) {
            if canCompleteTasks {
                Button(intent: ToggleTaskIntent(taskID: task.id)) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(done ? Color.green : board.accentColor(of: task))
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(board.accentColor(of: task))
                    .frame(width: 3, height: 11)
            }
            Text(task.title)
                .font(.caption)
                .lineLimit(1)
                .strikethrough(done)
                .foregroundStyle(done ? .secondary : .primary)
            if showMeta {
                ForEach(board.tags(for: task).prefix(3)) { tag in
                    TagMark(tag: tag, size: 6)
                }
            }
            Spacer(minLength: 0)
            if showMeta, p.total > 0 {
                Text("\(p.done)/\(p.total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if done, let completed = task.completedAt {
                HStack(spacing: 1) {
                    Image(systemName: "checkmark")
                    Text(completed.shortLabel)
                }
                .font(.caption2)
                .foregroundStyle(.green)
            } else if let d = task.nextDate, !done {
                let overdue = board.isOverdue(d, of: task)
                HStack(spacing: 1) {
                    Image(systemName: d.kind.symbol)
                    Text(d.date.shortLabel)
                }
                .font(.caption2)
                .foregroundStyle(overdue ? .red : d.kind.color)
            }
        }
    }

    private func subtaskRow(_ task: PlannerTask, _ sub: Subtask) -> some View {
        HStack(spacing: 4) {
            Button(intent: ToggleSubtaskIntent(taskID: task.id, subtaskID: sub.id)) {
                Image(systemName: sub.isDone ? "checkmark.square.fill" : "square")
                    .font(.system(size: 10))
                    .foregroundStyle(sub.isDone ? board.accentColor(of: task) : .secondary)
            }
            .buttonStyle(.plain)
            Text(sub.title)
                .font(.caption2)
                .lineLimit(1)
                .strikethrough(sub.isDone)
                .foregroundStyle(sub.isDone ? .tertiary : .secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
    }
}

struct PlannerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PlannerWidget", provider: Provider()) { entry in
            PlannerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Best Planner")
        .description("在桌面上查看你的任务看板。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct PlannerWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlannerWidget()
    }
}
