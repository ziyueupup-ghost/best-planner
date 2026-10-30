import Foundation

/// How a task repeats. When a repeating task is completed, the next one is created.
enum Recurrence: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly, biweekly, monthly, yearly
    /// Uses the task's `repeatRule` (every N days/weeks/months/years, chosen weekdays).
    case custom

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
        case .custom: L("自定义…")
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
        case .custom: return cal.date(byAdding: .day, value: 1, to: date)!   // real rule: RepeatRule
        }
    }

    func advance(_ date: Date, steps: Int) -> Date {
        (0..<steps).reduce(date) { d, _ in next(after: d) }
    }
}

/// A custom repetition: every `interval` days / weeks / months / years; for weeks,
/// optionally only on some weekdays (1 = Sunday … 7 = Saturday, as in Calendar).
struct RepeatRule: Codable, Hashable {
    enum Unit: String, Codable, CaseIterable, Identifiable, LenientEnum {
        case day, week, month, year
        static var fallback: Unit { .week }
        var id: String { rawValue }
        var title: String {
            switch self {
            case .day: L("天|repeat")
            case .week: L("周|repeat")
            case .month: L("个月|repeat")
            case .year: L("年|repeat")
            }
        }
    }

    var unit: Unit = .week
    var interval: Int = 1
    var weekdays: [Int] = []

    init(unit: Unit = .week, interval: Int = 1, weekdays: [Int] = []) {
        self.unit = unit
        self.interval = interval
        self.weekdays = weekdays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unit = (try? c.decodeIfPresent(Unit.self, forKey: .unit)) ?? .week
        interval = max(1, (try? c.decodeIfPresent(Int.self, forKey: .interval)) ?? 1)
        weekdays = (try? c.decodeIfPresent([Int].self, forKey: .weekdays)) ?? []
    }

    /// Monday first, as weeks are shown in China and Australia.
    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
    static func weekdayName(_ day: Int) -> String {
        [L("日|weekday"), L("一|weekday"), L("二|weekday"), L("三|weekday"), L("四|weekday"), L("五|weekday"), L("六|weekday")][(day - 1 + 7) % 7]
    }

    var title: String {
        let n = max(1, interval)
        if unit == .week, !weekdays.isEmpty {
            let days = RepeatRule.weekdayOrder.filter(weekdays.contains).map(RepeatRule.weekdayName).joined(separator: L("、|list"))
            return n == 1 ? L("每周\(days)") : L("每 \(n) 周的周\(days)")
        }
        switch unit {
        case .day: return n == 1 ? L("每天") : L("每 \(n) 天")
        case .week: return n == 1 ? L("每周") : L("每 \(n) 周")
        case .month: return n == 1 ? L("每月") : L("每 \(n) 个月")
        case .year: return n == 1 ? L("每年") : L("每 \(n) 年")
        }
    }

    /// The next date after `date` (same time of day).
    func next(after date: Date) -> Date {
        let cal = Calendar.current
        let n = max(1, interval)
        switch unit {
        case .day: return cal.date(byAdding: .day, value: n, to: date)!
        case .month: return cal.date(byAdding: .month, value: n, to: date)!
        case .year: return cal.date(byAdding: .year, value: n, to: date)!
        case .week:
            guard !weekdays.isEmpty else { return cal.date(byAdding: .day, value: 7 * n, to: date)! }
            // The next chosen weekday, in this week or every n-th week after it.
            var mondayCal = cal
            mondayCal.firstWeekday = 2
            let startWeek = mondayCal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            var d = date
            for _ in 0..<(7 * n + 7) {
                d = cal.date(byAdding: .day, value: 1, to: d)!
                let week = mondayCal.dateInterval(of: .weekOfYear, for: d)?.start ?? d
                let weeks = (cal.dateComponents([.day], from: startWeek, to: week).day ?? 0) / 7
                if weeks % n == 0, weekdays.contains(cal.component(.weekday, from: d)) { return d }
            }
            return cal.date(byAdding: .day, value: 7 * n, to: date)!
        }
    }
}

extension PlannerTask {
    /// "每周一、三" etc. for custom rules, otherwise the preset's name.
    var repeatTitle: String {
        recurrence == .custom ? (repeatRule ?? RepeatRule()).title : recurrence.title
    }

    /// The date one repetition after `date`.
    func nextRepeat(after date: Date) -> Date {
        recurrence == .custom ? (repeatRule ?? RepeatRule()).next(after: date) : recurrence.next(after: date)
    }

    func advanceRepeat(_ date: Date, steps: Int) -> Date {
        (0..<steps).reduce(date) { d, _ in nextRepeat(after: d) }
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

            // How many repetitions until the earliest date is no longer in the past (at least one).
            var steps = 1
            let anchor = original.dates.map(\.date).min()
            if let anchor {
                while original.advanceRepeat(anchor, steps: steps) < today, steps < 1000 { steps += 1 }
            }
            // With chosen weekdays, every date moves by the same number of days as the
            // earliest one, so their order (e.g. a subtask due the day before) is kept.
            let byWeekday = original.recurrence == .custom && original.repeatRule?.unit == .week
                && !(original.repeatRule?.weekdays.isEmpty ?? true)
            let shiftDays = anchor.map { a in
                Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: a),
                                                to: Calendar.current.startOfDay(for: original.advanceRepeat(a, steps: steps))).day ?? 0
            }
            func move(_ date: Date) -> Date {
                if byWeekday, let shiftDays { return Calendar.current.date(byAdding: .day, value: shiftDays, to: date) ?? date }
                return original.advanceRepeat(date, steps: steps)
            }

            var t = PlannerTask(title: original.title, columnID: target.id)
            t.notes = original.notes
            t.priorityID = original.priorityID
            t.tagIDs = original.tagIDs
            t.colorHex = original.colorHex
            t.backgroundHex = original.backgroundHex
            t.links = original.links
            t.recurrence = original.recurrence
            t.repeatRule = original.repeatRule
            t.contactIDs = original.contactIDs
            t.autoMoves = original.autoMoves.map { AutoMove(date: move($0.date), columnID: $0.columnID, hasTime: $0.hasTime) }
            t.subtasks = original.subtasks.map { s in
                Subtask(title: s.title, date: s.date.map(move), hasTime: s.hasTime)
            }
            t.dates = original.dates.map { d in
                TaskDate(kind: d.kind, date: move(d.date), note: d.note, hasTime: d.hasTime, moveTo: d.moveTo)
            }
            t.order = topOrder(in: target.id)
            record(from: nil, to: &t, oldColumns: columns)
            Board.appendHistory(&t, HistoryEntry(kind: .created, text: L("重复任务（\(original.repeatTitle)）自动生成")))
            created.append(t)
        }
        tasks.append(contentsOf: created)
        return created
    }
}
