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
        var t1 = PlannerTask(title: L("写周报"), columnID: "todo")
        t1.priorityID = "urgent"
        t1.tagIDs = [b.tags[0].id]
        t1.dates = [TaskDate(kind: .deadline, date: Date().addingTimeInterval(86_400))]
        var t2 = PlannerTask(title: L("设计新页面"), columnID: "doing")
        t2.subtasks = [Subtask(title: L("草图"), isDone: true), Subtask(title: L("高保真"))]
        var t3 = PlannerTask(title: L("回复邮件"), columnID: "todo")
        let today = Calendar.current.startOfDay(for: Date())
        t2.planDay = today; t2.planOrder = 1
        t1.planDay = today; t1.planOrder = 2
        t3.planDay = today; t3.planOrder = 3
        b.tasks = [t1, t2, t3, PlannerTask(title: L("整理笔记"), columnID: "done")]
        return b
    }
}

/// One line in the widget: an item on today's plan (numbered), a subtask shown under a
/// planned task, or "N more".
enum WidgetRow: Identifiable {
    case item(Int, PlanItem)
    case subtask(PlannerTask, Subtask)
    case more(Int)

    var id: String {
        switch self {
        case .item(_, let it): "i-\(it.id)"
        case .subtask(let t, let s): "s-\(t.id)-\(s.id)"
        case .more: "more"
        }
    }
}

/// Today's plan (日程), in the order it was put in: tick tasks (circles) and subtasks
/// (squares) right on the desktop.
struct PlannerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlannerEntry

    private var board: Board { entry.board }
    private var plan: [PlanItem] { board.plan(for: entry.date) }
    /// Ticking a task needs somewhere to move it.
    private var canCompleteTasks: Bool { board.columns.contains { $0.isDone } }

    private var budget: Int {
        switch family {
        case .systemSmall: 4
        case .systemLarge: 13
        default: 5
        }
    }

    var body: some View {
        let plan = plan
        let done = plan.filter { board.isDone($0) }.count
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("今天")).font(.headline)
                if family != .systemSmall {
                    Text(entry.date, format: .dateTime.month().day().weekday())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !plan.isEmpty {
                    Text("\(done)/\(plan.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !plan.isEmpty {
                ProgressView(value: Double(done), total: Double(plan.count))
                    .tint(Color(hex: "#2A78D6"))
                    .padding(.bottom, 2)
            }
            if plan.isEmpty {
                Spacer(minLength: 0)
                Text(L("今天还没有安排。")).font(.caption).foregroundStyle(.secondary)
                Text(L("在 Best Planner 的「日程」里把任务加到今天。")).font(.caption2).foregroundStyle(.tertiary)
            } else if done == plan.count {
                Spacer(minLength: 0)
                Text(L("今天的计划都完成了 🎉")).font(.caption).foregroundStyle(.secondary)
            } else {
                rowList(rows(plan))
            }
            Spacer(minLength: 0)
        }
    }

    /// Open items first in plan order (finished ones are left out to save room), each task
    /// followed by its open subtasks, cut off at the size's number of lines.
    private func rows(_ plan: [PlanItem]) -> [WidgetRow] {
        var out: [WidgetRow] = []
        let open = plan.enumerated().filter { !board.isDone($0.element) }
        var shown = 0
        for (i, it) in open {
            if out.count >= budget { break }
            out.append(.item(i + 1, it))
            shown += 1
            guard it.subtask == nil, family != .systemSmall else { continue }
            for s in it.task.subtasks where !s.isDone && out.count < budget {
                out.append(.subtask(it.task, s))
            }
        }
        if open.count > shown { out.append(.more(open.count - shown)) }
        return out
    }

    private func rowList(_ rows: [WidgetRow]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(rows) { row in
                switch row {
                case .item(let n, let it): itemRow(n, it)
                case .subtask(let t, let s): subtaskRow(t, s)
                case .more(let n):
                    Text(L("还有 \(n) 项…")).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func itemRow(_ n: Int, _ it: PlanItem) -> some View {
        let task = it.task
        return HStack(spacing: 5) {
            Text("\(n)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Color(hex: "#2A78D6")))
            if let sub = it.subtask {
                Button(intent: ToggleSubtaskIntent(taskID: task.id, subtaskID: sub.id)) {
                    Image(systemName: "square").font(.system(size: 11)).foregroundStyle(board.accentColor(of: task))
                }
                .buttonStyle(.plain)
            } else if canCompleteTasks {
                Button(intent: ToggleTaskIntent(taskID: task.id)) {
                    Image(systemName: "circle").font(.system(size: 12)).foregroundStyle(board.accentColor(of: task))
                }
                .buttonStyle(.plain)
            }
            Text(it.title).font(.caption).lineLimit(1)
            if family != .systemSmall {
                if it.subtask != nil {
                    Text("· \(task.title)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    ForEach(board.tags(for: task).prefix(2)) { TagMark(tag: $0, size: 6) }
                }
            }
            Spacer(minLength: 0)
            if family != .systemSmall, it.subtask == nil, let d = task.nextDate {
                HStack(spacing: 1) {
                    Image(systemName: d.kind.symbol)
                    Text(d.label)
                }
                .font(.caption2)
                .foregroundStyle(board.isOverdue(d, of: task) ? .red : d.kind.color)
            }
        }
    }

    private func subtaskRow(_ task: PlannerTask, _ sub: Subtask) -> some View {
        HStack(spacing: 4) {
            Button(intent: ToggleSubtaskIntent(taskID: task.id, subtaskID: sub.id)) {
                Image(systemName: "square")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Text(sub.title)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let label = sub.dateLabel {
                Text(label)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(sub.isOverdue ? Color.red : Color.secondary)
            }
        }
        .padding(.leading, 33)
    }
}

struct PlannerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PlannerWidget", provider: Provider()) { entry in
            PlannerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Best Planner")
        .description(L("在桌面上看今天的计划，直接打勾。"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct PlannerWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlannerWidget()
    }
}
