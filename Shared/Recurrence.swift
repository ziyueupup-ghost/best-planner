import Foundation

/// How a task repeats. When a repeating task is completed, the next one is created.
enum Recurrence: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly, biweekly, monthly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: L("不重复")
        case .daily: L("每天")
        case .weekdays: L("每个工作日")
        case .weekly: L("每周")
        case .biweekly: L("每两周")
        case .monthly: L("每月")
        case .yearly: L("每年")
        }
    }

    /// The date one repetition later (same time of day).
    func next(after date: Date) -> Date {
        let cal = Calendar.current
        switch self {
        case .none: return date
        case .daily: return cal.date(byAdding: .day, value: 1, to: date)!
        case .weekdays:
            var d = cal.date(byAdding: .day, value: 1, to: date)!
            while cal.isDateInWeekend(d) { d = cal.date(byAdding: .day, value: 1, to: d)! }
            return d
        case .weekly: return cal.date(byAdding: .day, value: 7, to: date)!
        case .biweekly: return cal.date(byAdding: .day, value: 14, to: date)!
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date)!
        case .yearly: return cal.date(byAdding: .year, value: 1, to: date)!
        }
    }

    func advance(_ date: Date, steps: Int) -> Date {
        (0..<steps).reduce(date) { d, _ in next(after: d) }
    }
}

extension Board {
    /// Creates the next occurrence for every repeating task that has been completed
    /// and hasn't spawned one yet. Dates move forward by whole repetitions until the
    /// earliest one is today or later; subtasks start unticked. Returns the new tasks.
    @discardableResult
    mutating func spawnRecurrences(now: Date = Date()) -> [PlannerTask] {
        guard let target = columns.first(where: { !$0.isDone }) else { return [] }
        let today = Calendar.current.startOfDay(for: now)
        var created: [PlannerTask] = []
        for i in tasks.indices where tasks[i].recurrence != .none && !tasks[i].recurrenceSpawned && isDone(tasks[i]) {
            tasks[i].recurrenceSpawned = true
            let original = tasks[i]
            let rule = original.recurrence

            // How many repetitions until the earliest date is no longer in the past (at least one).
            var steps = 1
            if let anchor = original.dates.map(\.date).min() {
                while rule.advance(anchor, steps: steps) < today, steps < 1000 { steps += 1 }
            }

            var t = PlannerTask(title: original.title, columnID: target.id)
            t.notes = original.notes
            t.priorityID = original.priorityID
            t.tagIDs = original.tagIDs
            t.colorHex = original.colorHex
            t.backgroundHex = original.backgroundHex
            t.links = original.links
            t.recurrence = rule
            t.subtasks = original.subtasks.map { Subtask(title: $0.title) }
            t.dates = original.dates.map { d in
                TaskDate(kind: d.kind, date: rule.advance(d.date, steps: steps), note: d.note)
            }
            t.order = topOrder(in: target.id)
            record(from: nil, to: &t, oldColumns: columns)
            Board.appendHistory(&t, HistoryEntry(kind: .created, text: L("重复任务（\(rule.title)）自动生成")))
            created.append(t)
        }
        tasks.append(contentsOf: created)
        return created
    }
}
