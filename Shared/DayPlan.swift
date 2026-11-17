import Foundation

// 今日: the tasks and subtasks picked for a day, in the order to do them. Kept on the items
// themselves (planDay + planOrder, on tasks and on subtasks) so it syncs and merges like
// any other field.

/// A task or one of its subtasks, on a day's plan.
struct PlanItem: Identifiable {
    var task: PlannerTask
    var subtask: Subtask?

    struct Ref: Hashable {
        var taskID: String
        var subtaskID: String?
    }

    var ref: Ref { Ref(taskID: task.id, subtaskID: subtask?.id) }
    var id: String { subtask.map { "\(task.id)/\($0.id)" } ?? task.id }
    var title: String { subtask?.title ?? task.title }
    var planDay: Date? { subtask?.planDay ?? task.planDay }
    var planOrder: Double { subtask?.planOrder ?? task.planOrder }
}

extension PlannerTask {
    /// On the plan for this day.
    func isPlanned(on day: Date) -> Bool {
        planDay.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
    }
}

extension Subtask {
    func isPlanned(on day: Date) -> Bool {
        planDay.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
    }
}

extension Board {
    /// Every task and subtask that has been put on some day's plan.
    private var planned: [PlanItem] {
        tasks.flatMap { t in
            (t.planDay == nil ? [] : [PlanItem(task: t)]) + t.subtasks.filter { $0.planDay != nil }.map { PlanItem(task: t, subtask: $0) }
        }
    }

    func isDone(_ item: PlanItem) -> Bool { item.subtask?.isDone ?? isDone(item.task) }

    /// The day's plan in its order (finished ones stay in place, shown ticked).
    func plan(for day: Date) -> [PlanItem] {
        planned.filter { $0.planDay.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { ($0.planOrder, $0.task.createdAt, $0.id) < ($1.planOrder, $1.task.createdAt, $1.id) }
    }

    /// Planned for an earlier day and still not finished (a subtask of a finished task counts as finished).
    func leftOver(before day: Date) -> [PlanItem] {
        let start = Calendar.current.startOfDay(for: day)
        return planned.filter { ($0.planDay.map { $0 < start } ?? false) && !isDone($0) && !isDone($0.task) }
            .sorted { ($0.planDay ?? .distantPast, $0.planOrder) < ($1.planDay ?? .distantPast, $1.planOrder) }
    }
}

extension Date {
    /// 今天, a weekday (周二) within a week either way, otherwise "12月6日 周日".
    var planDayName: String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: self)).day ?? 0
        if days == 0 { return L("今天") }
        return abs(days) < 7 ? formatted(.dateTime.weekday()) : formatted(.dateTime.month().day().weekday())
    }

    /// The next few days from today, for "加到…" menus.
    /// Today and the next six days.
    static var weekChoices: [Date] {
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: today)! }
    }

    static var planChoices: [Date] {
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        return (0..<4).map { cal.date(byAdding: .day, value: $0, to: today)! }
    }
}

extension Board {
    /// The status a task goes to once it's on today's plan: the one after the first
    /// (usually 进行中), unless that's a done status.
    var startedColumnID: String? {
        guard columns.count > 1, !columns[1].isDone else { return nil }
        return columns[1].id
    }

    /// A task still in the first status (待办) that is — itself or one of its subtasks — on
    /// today's plan moves to the next status (进行中), with a line in its history. Tasks
    /// still waiting for another one to finish (or start) stay where they are. `ids` limits
    /// it to these tasks (the ones just put on the plan).
    /// Returns how many moved.
    @discardableResult
    mutating func startTodaysPlan(now: Date = Date(), only ids: Set<String>? = nil) -> Int {
        guard let first = columns.first?.id, let target = startedColumnID else { return 0 }
        let cal = Calendar.current
        let oldColumns = columns
        var moved = 0
        for i in tasks.indices where tasks[i].columnID == first && (ids?.contains(tasks[i].id) ?? true) {
            let t0 = tasks[i]
            let planned = t0.planDay.map { cal.isDate($0, inSameDayAs: now) } ?? false
                || t0.subtasks.contains { s in s.planDay.map { cal.isDate($0, inSameDayAs: now) } ?? false }
            guard planned, unmetDependencies(of: t0, movingTo: target).isEmpty else { continue }
            var t = t0
            t.columnID = target
            t.order = topOrder(in: target)
            record(from: t0, to: &t, oldColumns: oldColumns)
            Board.appendHistory(&t, HistoryEntry(kind: .moved, text: L("📅 排进今天的计划，自动开始")))
            t.updatedAt = now
            tasks[i] = t
            moved += 1
        }
        return moved
    }
}
