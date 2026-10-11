import Foundation

// 回顾 and 成就: what got done each day, rebuilt from task history (completions,
// subtasks, notes, creation), focus sessions and the user's daily notes.

struct DayActivity {
    var completed: [(task: PlannerTask, at: Date)] = []
    var subtasks: [(task: PlannerTask, title: String, at: Date)] = []
    var created: [PlannerTask] = []
    var notes: [(task: PlannerTask, text: String, at: Date)] = []
    var focusMinutes = 0

    var isEmpty: Bool { completed.isEmpty && subtasks.isEmpty && created.isEmpty && notes.isEmpty && focusMinutes == 0 }
    /// Counts toward the streak: finished at least one task or subtask.
    var didSomething: Bool { !completed.isEmpty || !subtasks.isEmpty }
    /// 0…4 for the calendar heat colour.
    var level: Int {
        let score = Double(completed.count) + Double(subtasks.count) * 0.4 + Double(focusMinutes) / 25
        switch score {
        case 0: return 0
        case ..<2: return 1
        case ..<5: return 2
        case ..<9: return 3
        default: return 4
        }
    }
}

struct Achievement: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let progress: Int
    let target: Int
    /// When it was reached (nil = locked).
    let unlockedAt: Date?

    var isUnlocked: Bool { unlockedAt != nil }
}

struct ReviewData {
    let days: [Date: DayActivity]   // keyed by start of day
    let achievements: [Achievement]
    let currentStreak: Int
    let longestStreak: Int
    let totalCompleted: Int

    func activity(on day: Date) -> DayActivity {
        days[Calendar.current.startOfDay(for: day)] ?? DayActivity()
    }
}

extension Board {
    /// Every task, including deleted ones (their history still counts).
    private var allTasks: [PlannerTask] {
        var seen = Set<String>()
        return (tasks + trash).filter { seen.insert($0.id).inserted }
    }

    func review(now: Date = Date()) -> ReviewData {
        let cal = Calendar.current
        var days: [Date: DayActivity] = [:]
        func day(_ d: Date) -> Date { cal.startOfDay(for: d) }

        var completions: [(task: PlannerTask, at: Date)] = []
        var subtaskEvents: [Date] = []
        var sessions: [FocusSession] = []

        for task in allTasks {
            var completedDays = Set<Date>()
            for e in task.history {
                switch e.kind {
                case .completed where e.field == nil:
                    // One completion per task per day (reopen + complete again counts once).
                    if completedDays.insert(day(e.date)).inserted {
                        days[day(e.date), default: DayActivity()].completed.append((task, e.date))
                        completions.append((task, e.date))
                    }
                case .subtask where e.text.hasPrefix("完成子任务") || e.text.hasPrefix("Completed subtask"):
                    let title = Board.quoted(e.text) ?? e.text
                    days[day(e.date), default: DayActivity()].subtasks.append((task, title, e.date))
                    subtaskEvents.append(e.date)
                case .created where ["创建于", "复制自", "重复任务", "Created in", "Copied from", "Created by repeating"].contains(where: e.text.hasPrefix):
                    if !(days[day(e.date)]?.created.contains { $0.id == task.id } ?? false) {
                        days[day(e.date), default: DayActivity()].created.append(task)
                    }
                case .note where !["🍅", "添加附件", "移除附件", "Added attachment", "Removed attachment"].contains(where: e.text.hasPrefix):
                    days[day(e.date), default: DayActivity()].notes.append((task, e.text, e.date))
                default:
                    break
                }
            }
            // Tasks completed before history existed: use their completion date.
            if task.history.allSatisfy({ !($0.kind == .completed && $0.field == nil) }), let at = task.completedAt, isDone(task) {
                days[day(at), default: DayActivity()].completed.append((task, at))
                completions.append((task, at))
            }
            for s in task.focusSessions {
                days[day(s.start), default: DayActivity()].focusMinutes += s.minutes
                sessions.append(s)
            }
        }
        for key in dayNotes.keys { if let d = Board.dayKeyDate(key) { _ = days[d, default: DayActivity()] } }

        // Streaks over days that had a completed task or subtask.
        let active = Set(days.filter { $0.value.didSomething }.map(\.key))
        let today = day(now)
        var current = 0
        var cursor = active.contains(today) ? today : cal.date(byAdding: .day, value: -1, to: today)!
        while active.contains(cursor) {
            current += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        var longest = 0, run = 0, previous: Date?
        var streakReached: [Int: Date] = [:]   // streak length → first day it was reached
        for d in active.sorted() {
            if let p = previous, cal.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            longest = max(longest, run)
            if streakReached[run] == nil { streakReached[run] = d }
            previous = d
        }

        // Achievements.
        let completionDates = completions.map(\.at).sorted()
        let subtaskDates = subtaskEvents.sorted()
        let sessionsSorted = sessions.sorted { $0.start < $1.start }
        func nth(_ dates: [Date], _ n: Int) -> Date? { dates.count >= n ? dates[n - 1] : nil }
        func focusReached(_ minutes: Int) -> Date? {
            var total = 0
            for s in sessionsSorted { total += s.minutes; if total >= minutes { return s.start } }
            return nil
        }
        let totalFocus = sessions.reduce(0) { $0 + $1.minutes }
        let busiest = days.max { $0.value.completed.count < $1.value.completed.count }
        let tenDay = days.filter { $0.value.completed.count >= 10 }.keys.min()
        let early = completions.filter { cal.component(.hour, from: $0.at) < 8 }.map(\.at).min()
        let late = completions.filter { cal.component(.hour, from: $0.at) >= 23 }.map(\.at).min()
        let onTime = completions.filter { c in
            c.task.dates.contains { $0.kind == .deadline && c.at < cal.date(byAdding: .day, value: 1, to: day($0.date))! }
        }.map(\.at).sorted()
        let notedDays = dayNotes.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .keys.compactMap(Board.dayKeyDate).sorted()

        func count(_ id: String, _ icon: String, _ title: String, _ detail: String, _ dates: [Date], _ target: Int) -> Achievement {
            Achievement(id: id, icon: icon, title: title, detail: detail, progress: min(dates.count, target), target: target, unlockedAt: nth(dates, target))
        }
        func streak(_ id: String, _ icon: String, _ title: String, _ n: Int) -> Achievement {
            Achievement(id: id, icon: icon, title: title, detail: L("连续 \(n) 天都有完成"), progress: min(longest, n), target: n, unlockedAt: streakReached[n])
        }
        func focus(_ id: String, _ icon: String, _ title: String, _ hours: Int) -> Achievement {
            Achievement(id: id, icon: icon, title: title, detail: L("累计专注 \(hours) 小时"), progress: min(totalFocus / 60, hours), target: hours, unlockedAt: focusReached(hours * 60))
        }
        let achievements: [Achievement] = [
            count("done1", "🌱", L("第一步"), L("完成第 1 个任务"), completionDates, 1),
            count("done10", "✋", L("十全十美"), L("完成 10 个任务"), completionDates, 10),
            count("done50", "🏅", L("半百"), L("完成 50 个任务"), completionDates, 50),
            count("done100", "🏆", L("百战百胜"), L("完成 100 个任务"), completionDates, 100),
            count("done500", "👑", L("五百强"), L("完成 500 个任务"), completionDates, 500),
            count("sub50", "☑️", L("拆解大师"), L("完成 50 个子任务"), subtaskDates, 50),
            count("sub300", "🧩", L("细节控"), L("完成 300 个子任务"), subtaskDates, 300),
            streak("streak3", "🔥", L("三天连胜"), 3),
            streak("streak7", "⚡️", L("一周不断"), 7),
            streak("streak30", "🌋", L("月度坚持"), 30),
            Achievement(id: "focus1", icon: "🍅", title: L("第一个番茄"), detail: L("完成一次专注"), progress: min(sessions.count, 1), target: 1, unlockedAt: sessionsSorted.first?.start),
            focus("focus10", "⏳", L("专注 10 小时"), 10),
            focus("focus100", "🧘", L("专注 100 小时"), 100),
            Achievement(id: "busy10", icon: "🚀", title: L("高产的一天"), detail: L("一天完成 10 个任务"),
                        progress: min(busiest?.value.completed.count ?? 0, 10), target: 10, unlockedAt: tenDay),
            count("notes7", "📝", L("记录者"), L("写 7 天的今日总结"), notedDays, 7),
            Achievement(id: "early", icon: "🌅", title: L("早起鸟"), detail: L("早上 8 点前完成一个任务"), progress: early == nil ? 0 : 1, target: 1, unlockedAt: early),
            Achievement(id: "late", icon: "🦉", title: L("夜猫子"), detail: L("晚上 11 点后完成一个任务"), progress: late == nil ? 0 : 1, target: 1, unlockedAt: late),
            count("ontime20", "🎯", L("准时达人"), L("在截止日前完成 20 个任务"), onTime, 20),
        ]

        return ReviewData(days: days, achievements: achievements, currentStreak: current, longestStreak: longest,
                          totalCompleted: completionDates.count)
    }

    /// The text inside the first 「…」 or “…” (history entries quote names that way).
    static func quoted(_ text: String) -> String? {
        for (open, close) in [("「", "」"), ("“", "”")] {
            if let a = text.range(of: open), let b = text.range(of: close, range: a.upperBound..<text.endIndex) {
                return String(text[a.upperBound..<b.lowerBound])
            }
        }
        return nil
    }

    // MARK: Daily notes ("yyyy-MM-dd" → text)

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func dayKeyDate(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
}
