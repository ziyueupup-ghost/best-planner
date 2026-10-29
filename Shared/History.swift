import Foundation

// Task history and the edits that can also happen outside the app (desktop widget).
// Shared by the app and the widget so both record history the same way.

extension Board {
    func record(from old: PlannerTask?, to t: inout PlannerTask, oldColumns: [BoardColumn]) {
        let newColumn = column(t.columnID)
        let nowDone = newColumn?.isDone ?? false

        guard let old else {
            Board.appendHistory(&t, HistoryEntry(kind: .created, text: L("创建于「\(newColumn?.name ?? "")」")))
            if nowDone {
                t.completedAt = Date()
                Board.appendHistory(&t, HistoryEntry(kind: .completed, text: L("完成|history")))
            }
            return
        }

        let oldColumn = oldColumns.first { $0.id == old.columnID }
        let wasDone = oldColumn?.isDone ?? false

        if old.columnID != t.columnID {
            Board.appendHistory(&t, HistoryEntry(kind: .moved, text: L("从「\(oldColumn?.name ?? L("已删除的状态"))」移到「\(newColumn?.name ?? "")」")))
        }
        if nowDone && !wasDone {
            t.completedAt = Date()
            Board.appendHistory(&t, HistoryEntry(kind: .completed, text: L("完成|history")))
        } else if wasDone && !nowDone {
            t.completedAt = nil
            Board.appendHistory(&t, HistoryEntry(kind: .reopened, text: L("重新打开")))
        }

        // A new task is created as soon as its title has one character; finishing the
        // title and notes right after that is part of creating it, not an edit.
        let settingUp = Date().timeIntervalSince(t.createdAt) < 60
        if old.title != t.title, !t.title.isEmpty, !settingUp {
            Board.appendHistory(&t, HistoryEntry(kind: .edited, text: L("标题改为「\(t.title)」"), field: "title"))
        }
        if old.notes != t.notes, !settingUp {
            Board.appendHistory(&t, HistoryEntry(kind: .edited, text: L("修改了备注"), field: "notes"))
        }
        for link in t.links where !old.links.contains(where: { $0.id == link.id }) {
            Board.appendHistory(&t, HistoryEntry(kind: .note, text: L("添加附件「\(link.title)」")))
        }
        for link in old.links where !t.links.contains(where: { $0.id == link.id }) {
            Board.appendHistory(&t, HistoryEntry(kind: .note, text: L("移除附件「\(link.title)」")))
        }
        if old.recurrence != t.recurrence || old.repeatRule != t.repeatRule {
            Board.appendHistory(&t, HistoryEntry(kind: .edited, text: L("重复改为「\(t.repeatTitle)」"), field: "recurrence"))
        }
        if old.priorityID != t.priorityID {
            Board.appendHistory(&t, HistoryEntry(kind: .edited, text: L("优先级改为「\(priority(of: t).label)」"), field: "priority"))
        }
        for f in flags where t.flagIDs.contains(f.id) && !old.flagIDs.contains(f.id) {
            Board.appendHistory(&t, HistoryEntry(kind: .edited, text: L("标记进展「\(f.label)」")))
        }
        for f in flags where old.flagIDs.contains(f.id) && !t.flagIDs.contains(f.id) {
            Board.appendHistory(&t, HistoryEntry(kind: .edited, text: L("取消进展「\(f.label)」")))
        }
        for id in t.contactIDs where !old.contactIDs.contains(id) {
            Board.appendHistory(&t, HistoryEntry(kind: .edited, text: L("添加联系人「\(contact(id)?.name ?? "")」")))
        }
        for id in old.contactIDs where !t.contactIDs.contains(id) {
            Board.appendHistory(&t, HistoryEntry(kind: .edited, text: L("移除联系人「\(contact(id)?.name ?? "")」")))
        }

        for id in t.tagIDs where !old.tagIDs.contains(id) {
            Board.appendHistory(&t, HistoryEntry(kind: .tag, text: L("添加标签「\(tag(id)?.name ?? "")」")))
        }
        for id in old.tagIDs where !t.tagIDs.contains(id) {
            Board.appendHistory(&t, HistoryEntry(kind: .tag, text: L("移除标签「\(tag(id)?.name ?? "")」")))
        }

        let oldSubs = Dictionary(uniqueKeysWithValues: old.subtasks.map { ($0.id, $0) })
        let newIDs = Set(t.subtasks.map(\.id))
        for sub in t.subtasks {
            if let before = oldSubs[sub.id] {
                if !before.isDone && sub.isDone {
                    Board.appendHistory(&t, HistoryEntry(kind: .subtask, text: L("完成子任务「\(sub.title)」")))
                } else if before.isDone && !sub.isDone {
                    Board.appendHistory(&t, HistoryEntry(kind: .subtask, text: L("重新打开子任务「\(sub.title)」")))
                }
            } else {
                Board.appendHistory(&t, HistoryEntry(kind: .subtask, text: L("添加子任务「\(sub.title)」")))
            }
        }
        for sub in old.subtasks where !newIDs.contains(sub.id) {
            Board.appendHistory(&t, HistoryEntry(kind: .subtask, text: L("删除子任务「\(sub.title)」")))
        }

        let oldDates = Dictionary(uniqueKeysWithValues: old.dates.map { ($0.id, $0) })
        let newDateIDs = Set(t.dates.map(\.id))
        for d in t.dates {
            if let before = oldDates[d.id] {
                if before.date != d.date || before.kind != d.kind {
                    // Still within the merge window of "added": keep describing it as an addition.
                    let justAdded = t.history.last.map {
                        $0.field == "date-added-\(d.id)" && Date().timeIntervalSince($0.date) < 120
                    } ?? false
                    let text = justAdded ? L("添加\(d.kind.title)日期 \(d.showsTime ? d.date.dayTimeLabel : d.date.dayLabel)") : L("\(d.kind.title)日期改为 \(d.showsTime ? d.date.dayTimeLabel : d.date.dayLabel)")
                    Board.appendHistory(&t, HistoryEntry(kind: .date, text: text, field: justAdded ? "date-added-\(d.id)" : "date-\(d.id)"))
                }
            } else {
                Board.appendHistory(&t, HistoryEntry(kind: .date, text: L("添加\(d.kind.title)日期 \(d.showsTime ? d.date.dayTimeLabel : d.date.dayLabel)"), field: "date-added-\(d.id)"))
            }
        }
        for d in old.dates where !newDateIDs.contains(d.id) {
            Board.appendHistory(&t, HistoryEntry(kind: .date, text: L("删除\(d.kind.title)日期 \(d.showsTime ? d.date.dayTimeLabel : d.date.dayLabel)")))
        }
    }

    /// Appends an entry, merging it into the previous one when the same field was
    /// changed within the last two minutes (so typing doesn't flood the history).
    static func appendHistory(_ t: inout PlannerTask, _ entry: HistoryEntry) {
        if let field = entry.field, let last = t.history.last, last.field == field,
           entry.date.timeIntervalSince(last.date) < 120 {
            t.history[t.history.count - 1].text = entry.text
            t.history[t.history.count - 1].date = entry.date
        } else {
            t.history.append(entry)
        }
    }

    /// Copies a task into the same column, right above the original. Subtasks and dates
    /// get new ids so the copy is independent; history starts fresh.
    /// `resetChecks` unticks all subtasks (handy when reusing a task as a template).
    @discardableResult
    mutating func duplicateTask(_ id: String, resetChecks: Bool) -> PlannerTask? {
        guard let original = tasks.first(where: { $0.id == id }) else { return nil }
        var t = PlannerTask(title: original.title + L(" 副本"), columnID: original.columnID)
        t.notes = original.notes
        t.priorityID = original.priorityID
        t.tagIDs = original.tagIDs
        t.colorHex = original.colorHex
        t.backgroundHex = original.backgroundHex
        t.links = original.links
        t.recurrence = original.recurrence
        t.repeatRule = original.repeatRule
        t.flagIDs = original.flagIDs
        t.contactIDs = original.contactIDs
        t.autoMoves = original.autoMoves.map { var m = $0; m.id = UUID().uuidString; return m }
        t.dates = original.dates.map { d in
            var d = d
            d.id = UUID().uuidString
            return d
        }
        t.subtasks = original.subtasks.map { s in
            var s = s
            s.id = UUID().uuidString
            if resetChecks { s.isDone = false }
            return s
        }
        record(from: nil, to: &t, oldColumns: columns)
        Board.appendHistory(&t, HistoryEntry(kind: .created, text: L("复制自「\(original.title)」")))

        // Place it right above the original.
        var list = self.tasks(in: original.columnID)
        list.insert(t, at: list.firstIndex { $0.id == id } ?? 0)
        tasks.append(t)
        for (n, item) in list.enumerated() {
            if let i = tasks.firstIndex(where: { $0.id == item.id }) { tasks[i].order = Double(n) }
        }
        return tasks.first { $0.id == t.id }
    }

    /// Order value that puts a task at the top of a column.
    func topOrder(in columnID: String) -> Double {
        (tasks.filter { $0.columnID == columnID }.map(\.order).min() ?? 1) - 1
    }

    /// Ticks or unticks a subtask, recording it in the task's history.
    mutating func toggleSubtask(taskID: String, subtaskID: String, source: String? = nil) {
        edit(taskID, source: source) { t in
            if let j = t.subtasks.firstIndex(where: { $0.id == subtaskID }) { t.subtasks[j].isDone.toggle() }
        }
    }

    /// Ticking a task moves it to the first done column; unticking moves it back to the
    /// last column that isn't a done column. Completion date and history follow.
    mutating func toggleTaskDone(_ id: String, source: String? = nil) {
        guard let task = tasks.first(where: { $0.id == id }),
              let doneColumn = columns.first(where: \.isDone) else { return }
        let target = isDone(task) ? (columns.last { !$0.isDone } ?? columns[0]) : doneColumn
        let top = topOrder(in: target.id)
        edit(id, source: source) { t in
            t.columnID = target.id
            t.order = top
        }
    }

    /// Applies a change and records what changed. `source` (e.g. "桌面小组件") is
    /// appended to the new history entries so it's clear where the change came from.
    private mutating func edit(_ id: String, source: String?, _ change: (inout PlannerTask) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let old = tasks[i]
        var t = old
        change(&t)
        guard t != old else { return }
        let before = t.history.count
        record(from: old, to: &t, oldColumns: columns)
        if let source {
            for k in before..<t.history.count { t.history[k].text += " · \(source)" }
        }
        t.updatedAt = Date()
        tasks[i] = t
    }
}

extension Board {
    /// Carries out planned moves that are due: each task goes to the planned status (the
    /// latest due one wins when several are due at once) and those plans are removed.
    /// Returns how many tasks moved.
    @discardableResult
    mutating func applyDueMoves(now: Date = Date()) -> Int {
        var moved = 0
        let oldColumns = columns
        for i in tasks.indices where tasks[i].autoMoves.contains(where: { $0.dueDate <= now }) {
            let old = tasks[i]
            var t = old
            let due = t.autoMoves.filter { $0.dueDate <= now }.sorted { $0.dueDate < $1.dueDate }
            t.autoMoves.removeAll { $0.dueDate <= now }
            if let target = due.last(where: { column($0.columnID) != nil })?.columnID, target != t.columnID {
                t.columnID = target
                t.order = topOrder(in: target)
                record(from: old, to: &t, oldColumns: oldColumns)
                Board.appendHistory(&t, HistoryEntry(kind: .moved, text: L("⏩ 按计划自动移动")))
                moved += 1
            }
            tasks[i] = t
        }
        return moved
    }
}
