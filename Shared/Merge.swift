import Foundation

// Three-way merge for the task editor. The editor keeps its own copy of a task; meanwhile
// the same task can change elsewhere (ticked on the desktop widget, completed from the
// agenda, synced from another Mac). Saving the editor's copy as-is would undo those
// changes, so instead only what the editor changed (relative to the version it started
// from, `base`) is applied on top of the current stored task (`theirs`).

extension PlannerTask {
    /// `theirs` with the editor's changes (`mine` vs `base`) applied. When both sides
    /// changed the same thing, the editor wins.
    static func merge(base: PlannerTask, mine: PlannerTask, theirs: PlannerTask) -> PlannerTask {
        func pick<T: Equatable>(_ b: T, _ m: T, _ t: T) -> T { m != b ? m : t }
        var r = theirs
        r.title = pick(base.title, mine.title, theirs.title)
        r.notes = pick(base.notes, mine.notes, theirs.notes)
        r.columnID = pick(base.columnID, mine.columnID, theirs.columnID)
        r.priorityID = pick(base.priorityID, mine.priorityID, theirs.priorityID)
        r.colorHex = pick(base.colorHex, mine.colorHex, theirs.colorHex)
        r.backgroundHex = pick(base.backgroundHex, mine.backgroundHex, theirs.backgroundHex)
        r.recurrence = pick(base.recurrence, mine.recurrence, theirs.recurrence)
        r.repeatRule = pick(base.repeatRule, mine.repeatRule, theirs.repeatRule)
        r.notificationsOff = pick(base.notificationsOff, mine.notificationsOff, theirs.notificationsOff)
        r.tagIDs = mergeIDs(base: base.tagIDs, mine: mine.tagIDs, theirs: theirs.tagIDs)
        r.subtasks = mergeList(base: base.subtasks, mine: mine.subtasks, theirs: theirs.subtasks) { b, m, t in
            Subtask(id: t.id, title: pick(b.title, m.title, t.title), isDone: pick(b.isDone, m.isDone, t.isDone),
                    date: pick(b.date, m.date, t.date))
        }
        r.dates = mergeList(base: base.dates, mine: mine.dates, theirs: theirs.dates) { b, m, t in
            TaskDate(id: t.id, kind: pick(b.kind, m.kind, t.kind), date: pick(b.date, m.date, t.date), note: pick(b.note, m.note, t.note))
        }
        r.links = mergeList(base: base.links, mine: mine.links, theirs: theirs.links) { b, m, t in
            TaskLink(id: t.id, title: pick(b.title, m.title, t.title), url: pick(b.url, m.url, t.url))
        }
        return r
    }

    /// Whether the fields the editor can change are the same (ignores history, dates of
    /// creation/update, order, focus sessions…).
    func sameEditableContent(as other: PlannerTask) -> Bool {
        title == other.title && notes == other.notes && columnID == other.columnID && priorityID == other.priorityID
            && tagIDs == other.tagIDs && subtasks == other.subtasks && dates == other.dates && links == other.links
            && colorHex == other.colorHex && backgroundHex == other.backgroundHex && recurrence == other.recurrence && repeatRule == other.repeatRule
            && notificationsOff == other.notificationsOff
    }
}

/// Tag ids: keep `theirs`, add what `mine` added, remove what `mine` removed.
private func mergeIDs(base: [String], mine: [String], theirs: [String]) -> [String] {
    let added = mine.filter { !base.contains($0) }
    let removed = Set(base.filter { !mine.contains($0) })
    var result = theirs.filter { !removed.contains($0) }
    for id in added where !result.contains(id) { result.append(id) }
    return result
}

/// Items with ids (subtasks, dates, links): start from `theirs`; apply `mine`'s removals,
/// edits (field by field via `merge`), additions and reordering.
private func mergeList<E: Identifiable & Equatable>(base: [E], mine: [E], theirs: [E],
                                                    merge: (E, E, E) -> E) -> [E] where E.ID == String {
    let baseByID = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
    let mineIDs = Set(mine.map(\.id))
    var result = theirs.filter { !(baseByID[$0.id] != nil && !mineIDs.contains($0.id)) }   // removed in the editor
    for m in mine {
        if let b = baseByID[m.id] {
            if let i = result.firstIndex(where: { $0.id == m.id }) { result[i] = merge(b, m, result[i]) }
            // (deleted elsewhere but still in the editor: stays deleted unless the editor changed it)
            else if m != b { result.append(m) }
        } else if !result.contains(where: { $0.id == m.id }) {
            result.append(m)   // added in the editor
        }
    }
    // If the editor reordered or added items, follow its order; items only `theirs` has go last.
    let shared = mine.map(\.id).filter { baseByID[$0] != nil }
    let baseOrder = base.map(\.id).filter { mineIDs.contains($0) }
    if shared != baseOrder || mine.contains(where: { baseByID[$0.id] == nil }) {
        let position = Dictionary(uniqueKeysWithValues: mine.enumerated().map { ($1.id, $0) })
        result = result.enumerated().sorted { a, b in
            switch (position[a.element.id], position[b.element.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }
    return result
}

// MARK: - Whole board (the app saving over a file the widget changed meanwhile)

extension PlannerTask {
    /// Like `merge`, plus the fields the store manages: history entries and focus
    /// sessions from both sides are kept, completion/order follow whoever changed them.
    static func mergeAll(base: PlannerTask, mine: PlannerTask, theirs: PlannerTask) -> PlannerTask {
        func pick<T: Equatable>(_ b: T, _ m: T, _ t: T) -> T { m != b ? m : t }
        var r = merge(base: base, mine: mine, theirs: theirs)
        let theirHistory = Set(theirs.history.map(\.id))
        r.history = (theirs.history + mine.history.filter { !theirHistory.contains($0.id) }).sorted { $0.date < $1.date }
        let theirSessions = Set(theirs.focusSessions.map(\.id))
        r.focusSessions = theirs.focusSessions + mine.focusSessions.filter { !theirSessions.contains($0.id) }
        r.completedAt = pick(base.completedAt, mine.completedAt, theirs.completedAt)
        r.order = pick(base.order, mine.order, theirs.order)
        r.recurrenceSpawned = mine.recurrenceSpawned || theirs.recurrenceSpawned
        r.updatedAt = max(mine.updatedAt, theirs.updatedAt)
        return r
    }
}

extension Board {
    /// `theirs` (the file as it is now) with this app's changes since `base` (what it last
    /// read or wrote) applied on top. Tasks are merged one by one; additions and deletions
    /// on either side are kept; for settings, whichever side changed them wins.
    static func merge(base: Board, mine: Board, theirs: Board) -> Board {
        func pick<T: Equatable>(_ b: T, _ m: T, _ t: T) -> T { m != b ? m : t }
        var r = theirs
        r.columns = pick(base.columns, mine.columns, theirs.columns)
        r.tags = pick(base.tags, mine.tags, theirs.tags)
        r.sortMode = pick(base.sortMode, mine.sortMode, theirs.sortMode)
        r.expandedGroups = pick(base.expandedGroups, mine.expandedGroups, theirs.expandedGroups)
        r.priorities = pick(base.priorities, mine.priorities, theirs.priorities)
        r.defaultPriorityID = pick(base.defaultPriorityID, mine.defaultPriorityID, theirs.defaultPriorityID)
        r.subtaskPacks = pick(base.subtaskPacks, mine.subtaskPacks, theirs.subtaskPacks)
        r.widgetColumnIDs = pick(base.widgetColumnIDs, mine.widgetColumnIDs, theirs.widgetColumnIDs)
        r.widgetTagIDs = pick(base.widgetTagIDs, mine.widgetTagIDs, theirs.widgetTagIDs)
        var notes = theirs.dayNotes
        for key in Set(base.dayNotes.keys).union(mine.dayNotes.keys) where base.dayNotes[key] != mine.dayNotes[key] {
            notes[key] = mine.dayNotes[key]
        }
        r.dayNotes = notes
        r.tasks = mergeTasks(base: base.tasks, mine: mine.tasks, theirs: theirs.tasks)
        r.trash = mergeTasks(base: base.trash, mine: mine.trash, theirs: theirs.trash)
            .filter { t in !r.tasks.contains { $0.id == t.id } }
        return r
    }

    private static func mergeTasks(base: [PlannerTask], mine: [PlannerTask], theirs: [PlannerTask]) -> [PlannerTask] {
        let b = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        let m = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        let t = Dictionary(theirs.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        var out: [PlannerTask] = []
        for task in theirs {
            switch (b[task.id], m[task.id]) {
            case let (bt?, mt?): out.append(mt == bt ? task : PlannerTask.mergeAll(base: bt, mine: mt, theirs: task))
            case (_?, nil): break                              // deleted in this app
            case (nil, let mt?): out.append(mt)                // added on both sides (same id)
            case (nil, nil): out.append(task)                  // added elsewhere
            }
        }
        for task in mine where t[task.id] == nil {
            if let bt = b[task.id] {
                if task != bt { out.append(task) }              // deleted elsewhere, but edited here: keep
            } else {
                out.append(task)                                 // added in this app
            }
        }
        return out
    }
}
