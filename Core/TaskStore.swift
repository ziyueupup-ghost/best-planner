#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class BoardStore: ObservableObject {
    /// One store for the app, shared by the main window, quick add and the menu bar.
    static let shared = BoardStore()

    @Published private(set) var board: Board {
        willSet { registerUndo(from: board, to: newValue) }
    }
    private var pendingSave: Task<Void, Never>?

    // MARK: Undo
    /// The main window's undo manager (set by BoardView); ⌘Z / ⇧⌘Z in the Edit menu use it.
    weak var undoManager: UndoManager?
    private var isRestoring = false
    private var lastChange = Date.distantPast
    /// Modification date of the data file as of our last read/write; a different date
    /// means someone else (the desktop widget) changed it.
    private var knownFileDate: Date?
    private var watchTimer: Timer?
    /// The board as last read from / written to the file: the "base" for merging when
    /// the file changed elsewhere (the widget ticking something) before we save.
    private var syncedBoard: Board
    private var folderWatcher: DispatchSourceFileSystemObject?

    init() {
        let readable = PlannerStorage.read()
        // A data file that can't be read is kept as a backup before anything is written.
        if readable == nil, PlannerStorage.hasData { PlannerStorage.backup(force: true) }
        let loaded = readable ?? .empty
        board = loaded
        syncedBoard = loaded
        // Tasks completed before completion dates existed: use their last update.
        for i in board.tasks.indices where board.isDone(board.tasks[i]) && board.tasks[i].completedAt == nil {
            board.tasks[i].completedAt = board.tasks[i].updatedAt
        }
        // Daily backup; plus one the first time a new version opens the data (before it
        // writes anything), so an update can never cost more than this copy.
        let versionKey = "lastBackedUpVersion"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let firstRunOfVersion = UserDefaults.standard.string(forKey: versionKey) != appVersion
        PlannerStorage.backup(force: firstRunOfVersion)
        if firstRunOfVersion { PlannerStorage.backup() }
        UserDefaults.standard.set(appVersion, forKey: versionKey)
        // Deleted tasks are kept for 30 days.
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        board.trash.removeAll { ($0.deletedAt ?? .distantPast) < cutoff }
        // Boards from before manual ordering: freeze the current order so nothing jumps.
        for column in board.columns {
            let list = board.tasks(in: column.id)
            if Set(list.map(\.order)).count < list.count { renumber(list) }
        }
        // Write once so a migrated older board is persisted in the current format
        // (not when the file couldn't be read: leave it alone until there's a real edit).
        // (On iPhone the file may be an older iCloud copy not yet updated: don't write it
        // until there's a real edit, which merges first.)
        #if os(macOS)
        if readable != nil || !PlannerStorage.hasData { PlannerStorage.save(board) }
        #endif
        syncedBoard = board
        knownFileDate = PlannerStorage.modificationDate()
        ReminderScheduler.shared.reschedule(board)
        #if os(macOS)
        let willQuit = NSApplication.willTerminateNotification, didActivate = NSApplication.didBecomeActiveNotification
        #else
        // iOS apps are suspended rather than quit: save when going to the background.
        let willQuit = UIApplication.didEnterBackgroundNotification, didActivate = UIApplication.didBecomeActiveNotification
        #endif
        NotificationCenter.default.addObserver(forName: willQuit, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        NotificationCenter.default.addObserver(forName: didActivate, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfChangedElsewhere() }
        }
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfChangedElsewhere() }
        }
        watchDataFolder()
        #if os(iOS)
        // Ticks made on the widget while the app was closed.
        if absorbWidgetChanges() { persist() }
        #endif
    }

    /// Gets told right away when the data folder changes (the widget saving), instead of
    /// relying only on the timer, which macOS slows down while the app is in the background.
    private func watchDataFolder() {
        folderWatcher?.cancel()
        let fd = open(PlannerStorage.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reloadIfChangedElsewhere() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        folderWatcher = source
    }

    /// Picks up changes made by the desktop widget (ticking tasks/subtasks there).
    func reloadIfChangedElsewhere() {
        guard pendingSave == nil else { return }
        #if os(iOS)
        if absorbWidgetChanges() { flush(); return }
        #endif
        guard let date = PlannerStorage.modificationDate(), date != knownFileDate,
              let fresh = PlannerStorage.read() else { return }
        knownFileDate = date
        isRestoring = true   // not an undoable edit
        board = fresh
        isRestoring = false
        syncedBoard = board
        #if os(iOS)
        // New data from the Mac: show it on the widget too.
        if PlannerStorage.usesICloud {
            // Don't overwrite a tick the widget saved meanwhile: merge it in and save all.
            if absorbWidgetChanges() {
                flush()
                return
            }
            PlannerStorage.saveMirror(board)
            knownMirrorDate = PlannerStorage.mirrorModificationDate()
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
        ReminderScheduler.shared.reschedule(board)
    }

    /// One undo step per burst of edits: changes less than 0.8s apart (typing, a
    /// multi-part move) are merged. Opening/closing fold groups isn't undoable.
    private func registerUndo(from old: Board, to new: Board) {
        guard !isRestoring, let undoManager else { return }
        var a = old, b = new
        a.expandedGroups = []; b.expandedGroups = []
        guard a != b else { return }
        let now = Date()
        defer { lastChange = now }
        guard now.timeIntervalSince(lastChange) > 0.8 else { return }
        undoManager.registerUndo(withTarget: self) { $0.restore(old) }
        undoManager.setActionName(L("修改"))
    }

    private func restore(_ snapshot: Board) {
        let current = board
        undoManager?.registerUndo(withTarget: self) { $0.restore(current) }
        isRestoring = true
        board = snapshot
        isRestoring = false
        lastChange = .distantPast
        persist()
    }

    var columns: [BoardColumn] { board.columns }
    var tags: [Tag] { board.tags }
    var tasks: [PlannerTask] { board.tasks }

    func task(_ id: String) -> PlannerTask? { board.tasks.first { $0.id == id } }

    // MARK: Tasks

    func add(_ task: PlannerTask) {
        var t = task
        t.history = []
        t.order = topOrder(in: t.columnID)
        board.record(from: nil, to: &t, oldColumns: board.columns)
        board.tasks.append(t)
        persist()
    }

    /// Saves edits from the task editor. Only what the editor changed since `base` (the
    /// version it last synced with) is applied, so changes made elsewhere meanwhile — a
    /// subtask ticked on the widget, the task completed from the agenda — are kept.
    /// History, completion date, order and focus time stay the store's.
    func update(_ task: PlannerTask, base: PlannerTask) {
        modify(task.id) { t in
            let merged = PlannerTask.merge(base: base, mine: task, theirs: t)
            let columnChanged = merged.columnID != t.columnID
            t = merged
            if columnChanged { t.order = topOrder(in: merged.columnID) }
        }
    }

    /// Moves a task to another column, placing it at the top.
    func move(_ id: String, to columnID: String) {
        guard board.column(columnID) != nil, task(id)?.columnID != columnID else { return }
        let top = topOrder(in: columnID)
        modify(id) {
            $0.columnID = columnID
            $0.order = top
        }
    }

    // MARK: Ordering

    /// Drag-and-drop: puts a task directly above `targetID` (in that task's column),
    /// or at the end of `columnID` when there's no target. Switches to manual sorting,
    /// keeping everything else where it currently appears.
    func place(_ id: String, before targetID: String?, in columnID: String) {
        guard id != targetID, task(id) != nil else { return }
        let column = targetID.flatMap { task($0)?.columnID } ?? columnID
        guard board.column(column) != nil else { return }
        setSortMode(.manual)
        if task(id)?.columnID != column {
            modify(id) { $0.columnID = column }
        }
        var list = board.tasks(in: column).filter { $0.id != id }
        let index = targetID.flatMap { t in list.firstIndex { $0.id == t } } ?? list.count
        if let moved = task(id) { list.insert(moved, at: index) }
        renumber(list)
        persist()
    }

    func moveToTop(_ id: String) {
        guard let t = task(id), let first = board.tasks(in: t.columnID).first, first.id != id else { return }
        place(id, before: first.id, in: t.columnID)
    }

    func moveToBottom(_ id: String) {
        guard let t = task(id) else { return }
        place(id, before: nil, in: t.columnID)
    }

    func setSortMode(_ mode: SortMode) {
        guard board.sortMode != mode else { return }
        if mode == .manual {
            // Start manual order from what's on screen now.
            for column in board.columns { renumber(board.tasks(in: column.id)) }
        }
        board.sortMode = mode
        persist()
    }

    private func topOrder(in columnID: String) -> Double { board.topOrder(in: columnID) }

    /// Gives tasks consecutive order values matching the list (doesn't touch history).
    private func renumber(_ list: [PlannerTask]) {
        for (n, t) in list.enumerated() {
            if let i = board.tasks.firstIndex(where: { $0.id == t.id }) { board.tasks[i].order = Double(n) }
        }
    }

    func moveLeft(_ task: PlannerTask) {
        if let c = board.previousColumn(of: task) { move(task.id, to: c.id) }
    }

    func moveRight(_ task: PlannerTask) {
        if let c = board.nextColumn(of: task) { move(task.id, to: c.id) }
    }

    func toggleSubtask(_ taskID: String, _ subtaskID: String) {
        modify(taskID) { t in
            if let j = t.subtasks.firstIndex(where: { $0.id == subtaskID }) { t.subtasks[j].isDone.toggle() }
        }
    }

    func setCompletedAt(_ id: String, _ date: Date) {
        guard let i = board.tasks.firstIndex(where: { $0.id == id }), board.isDone(board.tasks[i]) else { return }
        board.tasks[i].completedAt = date
        Board.appendHistory(&board.tasks[i], HistoryEntry(kind: .completed, text: L("完成日期改为 \(date.dayLabel)"), field: "completedAt"))
        persist()
    }

    func addNote(_ id: String, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = board.tasks.firstIndex(where: { $0.id == id }) else { return }
        board.tasks[i].history.append(HistoryEntry(kind: .note, text: trimmed))
        persist()
    }

    func deleteHistoryEntry(_ taskID: String, _ entryID: String) {
        guard let i = board.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        board.tasks[i].history.removeAll { $0.id == entryID }
        persist()
    }

    @discardableResult
    func duplicate(_ id: String, resetChecks: Bool = false) -> PlannerTask? {
        let copy = board.duplicateTask(id, resetChecks: resetChecks)
        persist()
        return copy
    }

    // MARK: Multi-select

    /// Moves selected tasks to a status (to the top there).
    func moveTasks(_ ids: Set<String>, to columnID: String) {
        board.moveTasks(ids, to: columnID, placement: .top)
        persist()
    }

    /// Drag-and-drop of several tasks: above `targetID`, or at the end of the column.
    func placeTasks(_ ids: Set<String>, before targetID: String?, in columnID: String) {
        setSortMode(.manual)
        board.moveTasks(ids, to: columnID, placement: targetID.map { .before($0) } ?? .bottom)
        persist()
    }

    func shiftTasks(_ ids: Set<String>, by offset: Int) {
        setSortMode(.manual)
        board.shiftTasks(ids, by: offset)
        persist()
    }

    func moveTasksToEdge(_ ids: Set<String>, top: Bool) {
        setSortMode(.manual)
        board.moveTasksToEdge(ids, top: top)
        persist()
    }

    func deleteTasks(_ ids: Set<String>) {
        let removed = board.tasks.filter { ids.contains($0.id) }
        board.tasks.removeAll { ids.contains($0.id) }
        removed.forEach(trash)
        persist()
    }

    // MARK: Trash

    /// Moves a task to 最近删除 (restorable for 30 days).
    func delete(_ id: String) {
        guard let i = board.tasks.firstIndex(where: { $0.id == id }) else { return }
        trash(board.tasks.remove(at: i))
        persist()
    }

    /// Moves every task in a column to 最近删除.
    func clearColumn(_ columnID: String) {
        let removed = board.tasks.filter { $0.columnID == columnID }
        board.tasks.removeAll { $0.columnID == columnID }
        removed.forEach(trash)
        persist()
    }

    private func trash(_ task: PlannerTask) {
        var t = task
        t.deletedAt = Date()
        let column = board.column(t.columnID)?.name ?? ""
        Board.appendHistory(&t, HistoryEntry(kind: .moved, text: L("从「\(column)」删除")))
        board.trash.insert(t, at: 0)
    }

    /// Puts a deleted task back at the top of its column (or the first column if that's gone).
    func restore(_ id: String) {
        guard let i = board.trash.firstIndex(where: { $0.id == id }), let first = board.columns.first else { return }
        var t = board.trash.remove(at: i)
        t.deletedAt = nil
        if board.column(t.columnID) == nil { t.columnID = first.id }
        if board.isDone(t), t.completedAt == nil { t.completedAt = Date() }
        if !board.isDone(t) { t.completedAt = nil }
        t.order = board.topOrder(in: t.columnID)
        Board.appendHistory(&t, HistoryEntry(kind: .created, text: L("从「最近删除」恢复到「\(board.column(t.columnID)?.name ?? "")」")))
        board.tasks.append(t)
        persist()
    }

    func deleteForever(_ id: String) {
        board.trash.removeAll { $0.id == id }
        persist()
    }

    func emptyTrash() {
        board.trash.removeAll()
        persist()
    }

    // MARK: Column width

    /// nil returns the column to automatic width.
    func setColumnWidth(_ columnID: String, _ width: Double?) {
        guard let i = board.columns.firstIndex(where: { $0.id == columnID }) else { return }
        board.columns[i].width = width
        persist()
    }

    /// Applies a change to one task, then records what changed in its history.
    private func modify(_ id: String, _ change: (inout PlannerTask) -> Void) {
        guard let i = board.tasks.firstIndex(where: { $0.id == id }) else { return }
        let old = board.tasks[i]
        var t = old
        change(&t)
        guard t != old else { return }
        board.record(from: old, to: &t, oldColumns: board.columns)
        t.updatedAt = Date()
        board.tasks[i] = t
        persist()
    }

    // MARK: Folding

    func setFoldMode(_ columnID: String, _ mode: FoldMode) {
        guard let i = board.columns.firstIndex(where: { $0.id == columnID }) else { return }
        board.columns[i].foldMode = mode
        persist()
    }

    func toggleGroup(_ columnID: String, _ key: String) {
        let k = board.groupKey(columnID, key)
        if let i = board.expandedGroups.firstIndex(of: k) {
            board.expandedGroups.remove(at: i)
        } else {
            board.expandedGroups.append(k)
        }
        persist()
    }

    func moveGroup(_ key: String, before targetKey: String?, in columnID: String) {
        board.moveFoldGroup(key, before: targetKey, in: columnID)
        persist()
    }

    func shiftGroup(_ key: String, by offset: Int, in columnID: String) {
        board.shiftFoldGroup(key, by: offset, in: columnID)
        persist()
    }

    func resetGroupOrder(_ columnID: String) {
        guard let i = board.columns.firstIndex(where: { $0.id == columnID }) else { return }
        board.columns[i].groupOrder = []
        persist()
    }

    /// Opens or closes every group currently shown in a column.
    func setAllGroups(_ columnID: String, expanded: Bool) {
        guard let column = board.column(columnID) else { return }
        let keys = board.foldGroups(board.tasks(in: columnID), in: column).map { board.groupKey(columnID, $0.key) }
        board.expandedGroups.removeAll { keys.contains($0) }
        if expanded { board.expandedGroups.append(contentsOf: keys) }
        persist()
    }

    /// Done ⇄ not done (moves between the done column and the last open one).
    func toggleDone(_ id: String) {
        board.toggleTaskDone(id)
        persist()
    }

    // MARK: Focus

    func addFocusSession(_ taskID: String, start: Date, minutes: Int) {
        guard minutes > 0, let i = board.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        board.tasks[i].focusSessions.append(FocusSession(start: start, minutes: minutes))
        board.tasks[i].history.append(HistoryEntry(kind: .note, text: L("🍅 专注 \(minutes) 分钟")))
        persist()
    }

    // MARK: iCloud sync

    @Published private(set) var usesICloud = PlannerStorage.usesICloud

    /// Switches where the data lives, then reloads from there.
    func setICloudSync(_ on: Bool) throws {
        flush()
        try PlannerStorage.setICloud(on)
        usesICloud = PlannerStorage.usesICloud
        isRestoring = true   // switching location isn't an undoable edit
        if let moved = PlannerStorage.read() { board = moved }
        isRestoring = false
        syncedBoard = board
        knownFileDate = PlannerStorage.modificationDate()
        watchDataFolder()
        undoManager?.removeAllActions()
        flush()
    }

    // MARK: Daily notes

    func setDayNote(_ text: String, for day: Date) {
        let key = Board.dayKey(day)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard board.dayNotes[key] ?? "" != text else { return }
        if trimmed.isEmpty { board.dayNotes[key] = nil } else { board.dayNotes[key] = text }
        persist()
    }

    // MARK: Quick add

    /// Adds a task from a parsed quick-add line (creating new tags, applying linked packs).
    func quickAdd(_ p: QuickParse) {
        guard let first = board.columns.first, !p.title.isEmpty else { return }
        var t = PlannerTask(title: p.title, columnID: p.columnID ?? first.id)
        t.priorityID = p.priorityID ?? board.defaultPriorityID
        t.tagIDs = p.tagNames.map { addTag(named: $0).id }
        if let d = p.date { t.dates = [TaskDate(kind: p.dateKind, date: d)] }
        for tagID in t.tagIDs {
            for pack in board.packs(forTag: tagID) { t.apply(pack) }
        }
        add(t)
    }

    // MARK: Subtask packs

    /// Saves a list of subtasks as a new pack (from the task editor).
    func addPack(name: String, items: [String]) {
        let clean = items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return }
        board.subtaskPacks.append(SubtaskPack(name: name.isEmpty ? L("新子任务包") : name, icon: "📦", items: clean))
        persist()
    }

    // MARK: Tags

    @discardableResult
    func addTag(named name: String) -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing = board.tags.first(where: { $0.name == trimmed }) { return existing }
        let tag = Tag(name: trimmed, colorHex: Palette.next(after: board.tags.map(\.colorHex)))
        board.tags.append(tag)
        persist()
        return tag
    }

    // MARK: Settings

    /// Replaces columns and tags. Tasks in removed columns go to the first column;
    /// references to removed tags are dropped. Moves and completion changes caused by
    /// this (e.g. a column becoming a done column) are recorded in task history.
    func applySettings(columns: [BoardColumn], tags: [Tag], priorities: [PriorityLevel], defaultPriorityID: String,
                       packs: [SubtaskPack]) {
        guard let fallback = columns.first, !priorities.isEmpty else { return }
        let oldColumns = board.columns
        let columnIDs = Set(columns.map(\.id))
        let tagIDs = Set(tags.map(\.id))
        let priorityIDs = Set(priorities.map(\.id))
        board.columns = columns
        board.tags = tags
        board.priorities = priorities
        board.subtaskPacks = packs.map { p in
            var p = p
            p.autoTagIDs.removeAll { !tagIDs.contains($0) }
            return p
        }
        board.defaultPriorityID = priorityIDs.contains(defaultPriorityID) ? defaultPriorityID : priorities[0].id
        for i in board.tasks.indices {
            let old = board.tasks[i]
            var t = old
            if !columnIDs.contains(t.columnID) { t.columnID = fallback.id }
            if !priorityIDs.contains(t.priorityID) { t.priorityID = board.defaultPriorityID }
            t.tagIDs.removeAll { !tagIDs.contains($0) }
            let wasDone = oldColumns.first { $0.id == old.columnID }?.isDone ?? false
            if t != old || wasDone != board.isDone(t) {
                // Tag removals here come from deleting the tag itself; don't log those.
                var logged = old
                logged.tagIDs = t.tagIDs
                board.record(from: logged, to: &t, oldColumns: oldColumns)
                board.tasks[i] = t
            }
        }
        persist()
    }

    // MARK: Saving

    /// Every change is saved automatically. Rapid edits (typing) are coalesced
    /// into one write shortly after the last change.
    private func persist() {
        // Completing a repeating task creates its next occurrence right away.
        if board.tasks.contains(where: { $0.recurrence != .none && !$0.recurrenceSpawned && board.isDone($0) }) {
            board.spawnRecurrences()
        }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes immediately (also called when the app quits). If the file changed elsewhere
    /// since we last read it (the widget ticked something), merge instead of overwriting.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        #if os(iOS)
        _ = absorbWidgetChanges()
        #endif
        if let date = PlannerStorage.modificationDate(), date != knownFileDate, let theirs = PlannerStorage.read() {
            let merged = Board.merge(base: syncedBoard, mine: board, theirs: theirs)
            isRestoring = true   // bringing in someone else's change isn't an undoable edit
            board = merged
            isRestoring = false
        }
        PlannerStorage.save(board)
        syncedBoard = board
        knownFileDate = PlannerStorage.modificationDate()
        #if os(iOS)
        knownMirrorDate = PlannerStorage.mirrorModificationDate()
        #endif
        WidgetCenter.shared.reloadAllTimelines()
        ReminderScheduler.shared.reschedule(board)
    }

    // MARK: iPhone: widget copy and iCloud folder

    #if os(iOS)
    /// When the local copy last changed because of us; a different date means the widget
    /// ticked something there.
    private var knownMirrorDate: Date?

    /// Merges what the widget changed in the local copy into the board. Only needed while
    /// syncing with an iCloud folder (otherwise the local copy is the data file itself).
    @discardableResult
    private func absorbWidgetChanges() -> Bool {
        guard PlannerStorage.usesICloud, let date = PlannerStorage.mirrorModificationDate(), date != knownMirrorDate,
              let widgetBoard = PlannerStorage.readMirror() else { return false }
        knownMirrorDate = date
        // Base: what the widget started from (the copy as the app last wrote it).
        let base = PlannerStorage.readMirrorBase() ?? syncedBoard
        guard widgetBoard != base else { return false }
        let merged = Board.merge(base: base, mine: board, theirs: widgetBoard)
        guard merged != board else { return false }
        isRestoring = true
        board = merged
        isRestoring = false
        return true
    }

    enum FolderError: LocalizedError {
        case unreadable
        var errorDescription: String? {
            L("这个文件夹里的数据暂时读不出来（可能还在从 iCloud 下载），请稍后再试。")
        }
    }

    /// Starts syncing with the iCloud Drive folder the Mac uses. If it already has data
    /// (the Mac's), that data is used; this iPhone's own data is backed up first.
    func connectFolder(_ url: URL) throws {
        flush()
        let fm = FileManager.default
        let file = url.appendingPathComponent("planner.json")
        let hasCloudData = fm.fileExists(atPath: file.path)
            || fm.fileExists(atPath: url.appendingPathComponent(".planner.json.icloud").path)
        PlannerStorage.backup(force: true)
        let previous = PlannerStorage.pickedFolder
        PlannerStorage.pickedFolder = url
        if hasCloudData {
            guard let cloud = PlannerStorage.readCloudFile() else {
                PlannerStorage.pickedFolder = previous
                throw FolderError.unreadable
            }
            isRestoring = true
            board = cloud
            isRestoring = false
        } else {
            PlannerStorage.save(board)
        }
        usesICloud = true
        syncedBoard = board
        knownFileDate = PlannerStorage.modificationDate()
        PlannerStorage.save(board)   // refreshes the widget's copy
        knownMirrorDate = PlannerStorage.mirrorModificationDate()
        knownFileDate = PlannerStorage.modificationDate()
        watchDataFolder()
        WidgetCenter.shared.reloadAllTimelines()
        ReminderScheduler.shared.reschedule(board)
    }

    /// Stops syncing: keeps working on this iPhone's copy.
    func disconnectFolder() {
        flush()
        PlannerStorage.pickedFolder = nil
        usesICloud = false
        knownFileDate = PlannerStorage.modificationDate()
        knownMirrorDate = PlannerStorage.mirrorModificationDate()
        watchDataFolder()
    }
    #endif
}
