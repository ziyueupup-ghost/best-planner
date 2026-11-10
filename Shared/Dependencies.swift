import Foundation

// Task dependencies, like the links in a Gantt chart: "this task can only start (or
// finish) once that one has finished (or started)". On the board a task counts as
// started once it has left the first status, and finished once it's in a done status.
// Nothing is moved automatically: a task that's still waiting is marked on its card, and
// moving it anyway asks first.

enum DependencyKind: String, Codable, CaseIterable, Identifiable {
    case finishToStart, startToStart, finishToFinish, startToFinish

    var id: String { rawValue }

    /// The other task has to be finished (otherwise: just started).
    var needsOtherFinished: Bool { self == .finishToStart || self == .finishToFinish }
    /// Holds back starting this task (otherwise: finishing it).
    var gatesStart: Bool { self == .finishToStart || self == .startToStart }

    /// "等「A」完成，才能开始" etc., for a dependency on `other`.
    func sentence(_ other: String) -> String {
        switch self {
        case .finishToStart: L("等「\(other)」完成，才能开始")
        case .startToStart: L("等「\(other)」开始，才能开始")
        case .finishToFinish: L("等「\(other)」完成，才能完成")
        case .startToFinish: L("等「\(other)」开始，才能完成")
        }
    }

    /// Short name for the kind menu.
    var title: String {
        switch self {
        case .finishToStart: L("它完成后，才能开始")
        case .startToStart: L("它开始后，才能开始")
        case .finishToFinish: L("它完成后，才能完成")
        case .startToFinish: L("它开始后，才能完成")
        }
    }
}

struct TaskDependency: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    /// The task this one waits for.
    var taskID: String
    var kind: DependencyKind = .finishToStart

    init(id: String = UUID().uuidString, taskID: String, kind: DependencyKind = .finishToStart) {
        self.id = id
        self.taskID = taskID
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        taskID = try c.decodeIfPresent(String.self, forKey: .taskID) ?? ""
        kind = (try? c.decodeIfPresent(DependencyKind.self, forKey: .kind)) ?? .finishToStart
    }
}

extension Board {
    /// Left the first status (or finished).
    func isStarted(_ task: PlannerTask) -> Bool {
        isDone(task) || task.columnID != columns.first?.id
    }

    /// Whether what this dependency waits for has happened. A dependency on a task that
    /// no longer exists (deleted) doesn't hold anything back.
    func isMet(_ d: TaskDependency) -> Bool {
        guard let other = tasks.first(where: { $0.id == d.taskID }) else { return true }
        return d.kind.needsOtherFinished ? isDone(other) : isStarted(other)
    }

    /// What the task is still waiting for at its next step: to start (while it hasn't),
    /// then to finish. Empty when it's free to go on (or already finished).
    func waitingOn(_ task: PlannerTask) -> [TaskDependency] {
        guard !isDone(task) else { return [] }
        let started = isStarted(task)
        return task.dependencies.filter { started ? !$0.kind.gatesStart && !isMet($0) : $0.kind.gatesStart && !isMet($0) }
    }

    /// The dependencies a move would break: starting the task (leaving the first status)
    /// before what gates its start, or finishing it before anything it waits for.
    func unmetDependencies(of task: PlannerTask, movingTo columnID: String) -> [TaskDependency] {
        guard let target = column(columnID), columnID != task.columnID else { return [] }
        if target.isDone { return isDone(task) ? [] : task.dependencies.filter { !isMet($0) } }
        let starts = !isStarted(task) && columnID != columns.first?.id
        return starts ? task.dependencies.filter { $0.kind.gatesStart && !isMet($0) } : []
    }

    /// Tasks (not finished) that have a dependency on this one.
    func dependents(of id: String) -> [PlannerTask] {
        tasks.filter { t in !isDone(t) && t.dependencies.contains { $0.taskID == id } }
    }

    /// Making `taskID` wait for `otherID` would close a loop (A waits for B waits for A).
    func wouldLoop(_ taskID: String, waitingFor otherID: String) -> Bool {
        var seen: Set<String> = []
        var stack = [otherID]
        while let id = stack.popLast() {
            if id == taskID { return true }
            guard seen.insert(id).inserted, let t = tasks.first(where: { $0.id == id }) else { continue }
            stack += t.dependencies.map(\.taskID)
        }
        return false
    }

    /// "等「A」完成，才能开始" for the first of these, plus how many more.
    func describe(_ deps: [TaskDependency]) -> String {
        guard let first = deps.first else { return "" }
        let name = tasks.first { $0.id == first.taskID }?.title ?? L("已删除的任务")
        let text = first.kind.sentence(name)
        return deps.count > 1 ? L("\(text)（还有 \(deps.count - 1) 个）") : text
    }
}

// MARK: Gantt bars

extension PlannerTask {
    /// The task's bar on the Gantt chart, by day: from its (earliest) 开始 date to its
    /// (latest) 截止 date. With only one of the two it's a one-day bar; with neither, none.
    var ganttSpan: (start: Date, end: Date)? {
        let cal = Calendar.current
        let start = dates.filter { $0.kind == .start }.map(\.date).min()
        let end = dates.filter { $0.kind == .deadline }.map(\.date).max()
        guard let first = start ?? end, let last = end ?? start else { return nil }
        let a = cal.startOfDay(for: first), b = cal.startOfDay(for: last)
        return (min(a, b), max(a, b))
    }

    /// Sets the bar to these days: moves the 开始 / 截止 dates (keeping their time of day),
    /// adding the missing one only when the bar is longer than a day.
    mutating func setGanttSpan(start: Date, end: Date) {
        let cal = Calendar.current
        func onDay(_ old: Date, _ day: Date) -> Date {
            let c = cal.dateComponents([.hour, .minute], from: old)
            return cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day) ?? day
        }
        let startIndex = dates.indices.filter { dates[$0].kind == .start }.min { dates[$0].date < dates[$1].date }
        let endIndex = dates.indices.filter { dates[$0].kind == .deadline }.max { dates[$0].date < dates[$1].date }
        let sameDay = cal.isDate(start, inSameDayAs: end)
        if let i = startIndex { dates[i].date = onDay(dates[i].date, start) }
        else if !sameDay || endIndex == nil { dates.append(TaskDate(kind: .start, date: cal.startOfDay(for: start))) }
        if let i = endIndex { dates[i].date = onDay(dates[i].date, end) }
        else if !sameDay { dates.append(TaskDate(kind: .deadline, date: cal.startOfDay(for: end))) }
    }
}
