import SwiftUI

/// How a column folds its tasks into collapsible groups. Set per column.
enum FoldMode: String, Codable, CaseIterable, Identifiable {
    case off, all, tag, priority, date

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: L("不折叠")
        case .all: L("整列折叠")
        case .tag: L("按标签折叠")
        case .priority: L("按优先级折叠")
        case .date: L("按日期折叠")
        }
    }

    var symbol: String {
        switch self {
        case .off: "list.bullet"
        case .all: "rectangle.compress.vertical"
        case .tag: "tag"
        case .priority: "exclamationmark.circle"
        case .date: "calendar"
        }
    }
}

/// One collapsible group of tasks inside a column.
struct FoldGroup: Identifiable {
    enum Header {
        case text(String, symbol: String, color: Color)
        case tag(Tag)
        case priority(PriorityLevel)
    }

    let key: String
    let header: Header
    let tasks: [PlannerTask]

    var id: String { key }
}

extension Board {
    func groupKey(_ columnID: String, _ key: String) -> String { "\(columnID)|\(key)" }

    /// A column's tasks in the order the board shows them: the sort order, and when the
    /// column is folded into groups, group by group in the column's group order.
    /// The widget uses this so its order always matches the app.
    func displayOrder(in columnID: String) -> [PlannerTask] {
        let sorted = tasks(in: columnID)
        guard let column = column(columnID), column.foldMode != .off, column.foldMode != .all else { return sorted }
        return foldGroups(sorted, in: column).flatMap(\.tasks)
    }

    func isGroupExpanded(_ columnID: String, _ key: String) -> Bool {
        expandedGroups.contains(groupKey(columnID, key))
    }

    /// Splits a column's (already sorted) tasks into groups for its fold mode, in the
    /// column's custom group order if it has one (groups not in it keep their default
    /// position after the ordered ones). Empty groups are left out.
    func foldGroups(_ tasks: [PlannerTask], in column: BoardColumn) -> [FoldGroup] {
        let groups = defaultFoldGroups(tasks, in: column)
        guard !column.groupOrder.isEmpty else { return groups }
        let rank = Dictionary(column.groupOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return groups.enumerated().sorted { a, b in
            let ra = rank[a.element.key] ?? Int.max, rb = rank[b.element.key] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// Moves a fold group in a column: before `targetKey`, or to the end when nil.
    mutating func moveFoldGroup(_ key: String, before targetKey: String?, in columnID: String) {
        guard key != targetKey, let ci = columns.firstIndex(where: { $0.id == columnID }) else { return }
        let visible = foldGroups(self.tasks(in: columnID), in: columns[ci]).map(\.key)
        guard visible.contains(key) else { return }
        var order = visible.filter { $0 != key }
        let index = targetKey.flatMap { order.firstIndex(of: $0) } ?? order.count
        order.insert(key, at: index)
        // Keep remembered positions of groups that are empty right now.
        columns[ci].groupOrder = order + columns[ci].groupOrder.filter { !order.contains($0) }
    }

    /// Up (-1) / down (+1) by one place.
    mutating func shiftFoldGroup(_ key: String, by offset: Int, in columnID: String) {
        guard let column = column(columnID) else { return }
        let keys = foldGroups(self.tasks(in: columnID), in: column).map(\.key)
        guard let i = keys.firstIndex(of: key) else { return }
        let target = i + offset
        guard target >= 0, target < keys.count else { return }
        // Moving down = inserting before the group two places below (or at the end).
        let before = offset < 0 ? keys[target] : (target + 1 < keys.count ? keys[target + 1] : nil)
        moveFoldGroup(key, before: before, in: columnID)
    }

    private func defaultFoldGroups(_ tasks: [PlannerTask], in column: BoardColumn) -> [FoldGroup] {
        switch column.foldMode {
        case .off:
            return []
        case .all:
            return [FoldGroup(key: "all", header: .text(L("全部任务"), symbol: "tray.full", color: column.color), tasks: tasks)]
        case .tag:
            // A task with several tags goes under its first one.
            var groups = tags.map { tag in
                FoldGroup(key: "tag-\(tag.id)", header: .tag(tag),
                          tasks: tasks.filter { t in t.tagIDs.first { self.tag($0) != nil } == tag.id })
            }
            groups.append(FoldGroup(key: "tag-none", header: .text(L("无标签"), symbol: "tag.slash", color: .secondary),
                                    tasks: tasks.filter { t in !t.tagIDs.contains { self.tag($0) != nil } }))
            return groups.filter { !$0.tasks.isEmpty }
        case .priority:
            return priorities.map { p in
                FoldGroup(key: "priority-\(p.id)", header: .priority(p),
                          tasks: tasks.filter { priority(of: $0).id == p.id })
            }.filter { !$0.tasks.isEmpty }
        case .date:
            let buckets = column.isDone ? DateBucket.completed : DateBucket.upcoming
            return buckets.map { b in
                FoldGroup(key: "date-\(b.key)", header: .text(b.title, symbol: b.symbol, color: b.color),
                          tasks: tasks.filter { b.contains(column.isDone ? $0.completedAt : $0.nextDate?.date) })
            }.filter { !$0.tasks.isEmpty }
        }
    }
}

/// Date ranges used by 按日期折叠: completion dates in done columns, upcoming dates elsewhere.
private struct DateBucket {
    let key: String
    let title: String
    let symbol: String
    let color: Color
    let contains: (Date?) -> Bool

    private static var cal: Calendar { Calendar.current }
    private static var today: Date { cal.startOfDay(for: Date()) }
    private static func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
    private static func sameWeek(_ d: Date) -> Bool { cal.isDate(d, equalTo: Date(), toGranularity: .weekOfYear) }
    private static func sameMonth(_ d: Date) -> Bool { cal.isDate(d, equalTo: Date(), toGranularity: .month) }

    static let completed: [DateBucket] = [
        DateBucket(key: "today", title: L("今天完成"), symbol: "sun.max", color: .orange) { d in d.map { cal.isDateInToday($0) } ?? false },
        DateBucket(key: "yesterday", title: L("昨天完成"), symbol: "moon", color: .indigo) { d in d.map { cal.isDateInYesterday($0) } ?? false },
        DateBucket(key: "week", title: L("本周完成"), symbol: "calendar", color: .blue) { d in
            guard let d else { return false }
            return d < day(-1) && sameWeek(d)
        },
        DateBucket(key: "month", title: L("本月完成"), symbol: "calendar.circle", color: .teal) { d in
            guard let d else { return false }
            return d < day(-1) && !sameWeek(d) && sameMonth(d)
        },
        DateBucket(key: "earlier", title: L("更早完成"), symbol: "archivebox", color: .gray) { d in
            guard let d else { return true }
            return d < day(-1) && !sameWeek(d) && !sameMonth(d)
        },
    ]

    static let upcoming: [DateBucket] = [
        DateBucket(key: "overdue", title: L("已过期"), symbol: "exclamationmark.triangle", color: .red) { d in d.map { $0 < today } ?? false },
        DateBucket(key: "today", title: L("今天"), symbol: "sun.max", color: .orange) { d in d.map { cal.isDateInToday($0) } ?? false },
        DateBucket(key: "tomorrow", title: L("明天"), symbol: "sunrise", color: .yellow) { d in d.map { cal.isDateInTomorrow($0) } ?? false },
        DateBucket(key: "week", title: L("本周"), symbol: "calendar", color: .blue) { d in
            guard let d else { return false }
            return d >= day(2) && sameWeek(d)
        },
        DateBucket(key: "later", title: L("以后"), symbol: "calendar.badge.clock", color: .purple) { d in
            guard let d else { return false }
            return d >= day(2) && !sameWeek(d)
        },
        DateBucket(key: "none", title: L("无日期"), symbol: "calendar.badge.minus", color: .gray) { d in d == nil },
    ]
}
