import Foundation

// 今天 / 即将到来: open tasks by date, across all statuses.

struct AgendaSection: Identifiable {
    let id: String
    let title: String
    let tasks: [PlannerTask]
    var isOverdue = false
}

extension Board {
    /// The date that puts a task on the agenda: an overdue 截止 if it has one,
    /// otherwise its earliest date from today on. Done tasks aren't on the agenda.
    func agendaDate(_ task: PlannerTask, now: Date = Date()) -> Date? {
        guard !isDone(task) else { return nil }
        let today = Calendar.current.startOfDay(for: now)
        if let overdue = task.sortedDates.first(where: { $0.kind == .deadline && $0.date < today }) { return overdue.date }
        return task.sortedDates.first { $0.date >= today }?.date
    }

    /// Open tasks dated up to the end of `days` days from today (0 = today), overdue included.
    func agendaTasks(through days: Int, now: Date = Date()) -> [PlannerTask] {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: days + 1, to: cal.startOfDay(for: now))!
        return tasks.compactMap { t in agendaDate(t, now: now).map { (t, $0) } }
            .filter { $0.1 < end }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : priorityRank($0.0) < priorityRank($1.0) }
            .map(\.0)
    }

    /// 已过期, 今天, 明天, then one section per day for the rest of `days`, then 以后.
    func agendaSections(days: Int = 7, includeLater: Bool = true, now: Date = Date()) -> [AgendaSection] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let dated = tasks.compactMap { t in agendaDate(t, now: now).map { (task: t, date: $0) } }
            .sorted { $0.date != $1.date ? $0.date < $1.date : priorityRank($0.task) < priorityRank($1.task) }
        var sections: [AgendaSection] = []
        let overdue = dated.filter { $0.date < today }.map(\.task)
        if !overdue.isEmpty { sections.append(AgendaSection(id: "overdue", title: L("已过期"), tasks: overdue, isOverdue: true)) }
        for offset in 0...days {
            let start = cal.date(byAdding: .day, value: offset, to: today)!
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let items = dated.filter { $0.date >= start && $0.date < end }.map(\.task)
            let name = offset == 0 ? L("今天") : offset == 1 ? L("明天") : offset == 2 ? L("后天") : ""
            let label = start.formatted(.dateTime.month().day().weekday())
            sections.append(AgendaSection(id: "day-\(offset)", title: name.isEmpty ? label : "\(name) · \(label)", tasks: items))
        }
        if includeLater {
            let limit = cal.date(byAdding: .day, value: days + 1, to: today)!
            let later = dated.filter { $0.date >= limit }.map(\.task)
            if !later.isEmpty { sections.append(AgendaSection(id: "later", title: L("以后"), tasks: later)) }
        }
        return sections
    }
}
