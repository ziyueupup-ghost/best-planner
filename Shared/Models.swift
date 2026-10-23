#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import Foundation
import SwiftUI

// MARK: - Board structure

/// A status column. Users can add, rename, recolor, reorder and delete these.
struct BoardColumn: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var colorHex: String
    /// Tasks in a "done" column count as finished (progress, overdue, strikethrough).
    var isDone: Bool = false
    /// Optional emoji shown in the column header.
    var icon: String = ""
    /// How tasks in this column are folded into collapsible groups.
    var foldMode: FoldMode = .off
    /// Custom width in points (at 100% font size); nil shares the window evenly.
    var width: Double?
    /// User's order of fold groups in this column (group keys); empty = default order.
    var groupOrder: [String] = []

    var color: Color { Color(hex: colorHex) }

    init(id: String = UUID().uuidString, name: String, colorHex: String, isDone: Bool = false, icon: String = "") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isDone = isDone
        self.icon = icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#888888"
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        foldMode = (try? c.decodeIfPresent(FoldMode.self, forKey: .foldMode)) ?? .off
        width = try c.decodeIfPresent(Double.self, forKey: .width)
        groupOrder = try c.decodeIfPresent([String].self, forKey: .groupOrder) ?? []
        if let icon = try c.decodeIfPresent(String.self, forKey: .icon) {
            self.icon = icon
        } else {
            // Boards from before icons existed: give the built-in columns their default icon.
            self.icon = Board.defaultColumns.first { $0.id == id }?.icon ?? ""
        }
    }
}

enum SortMode: String, Codable, CaseIterable, Identifiable {
    case manual, priority, date, created

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: L("手动排序（拖动调整）")
        case .priority: L("按优先级")
        case .date: L("按日期")
        case .created: L("按创建时间")
        }
    }
}

/// A contact / collaborator. Kept on the board once used, so they can be picked again.
struct Contact: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var email: String = ""
    var phone: String = ""

    init(id: String = UUID().uuidString, name: String, email: String = "", phone: String = "") {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        email = (try? c.decodeIfPresent(String.self, forKey: .email)) ?? ""
        phone = (try? c.decodeIfPresent(String.self, forKey: .phone)) ?? ""
    }
}

/// How a task is going ("顺利进行", "卡住了", "需要跟进"…). Users define the list;
/// a task has at most one, shown on its card.
struct ProgressFlag: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var colorHex: String
    var icon: String = ""

    var color: Color { Color(hex: colorHex) }
    var label: String { icon.isEmpty ? name : "\(icon) \(name)" }

    init(id: String = UUID().uuidString, name: String, colorHex: String, icon: String = "") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        colorHex = (try? c.decodeIfPresent(String.self, forKey: .colorHex)) ?? "#888888"
        icon = (try? c.decodeIfPresent(String.self, forKey: .icon)) ?? ""
    }
}

/// A priority level. Users can add, rename, recolor, reorder and give them emoji.
/// Order in `Board.priorities` is the ranking: first is the most important.
struct PriorityLevel: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var colorHex: String
    var icon: String = ""

    var color: Color { Color(hex: colorHex) }
    /// "🔥 紧急", or just the name.
    var label: String { icon.isEmpty ? name : "\(icon) \(name)" }

    init(id: String = UUID().uuidString, name: String, colorHex: String, icon: String = "") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#888888"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
    }
}

enum DateKind: String, Codable, CaseIterable, Identifiable {
    case deadline, milestone, start, reminder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deadline: L("截止")
        case .milestone: L("里程碑")
        case .start: L("开始")
        case .reminder: L("提醒")
        }
    }

    var symbol: String {
        switch self {
        case .deadline: "exclamationmark.circle"
        case .milestone: "flag.fill"
        case .start: "play.circle"
        case .reminder: "bell"
        }
    }

    var color: Color {
        switch self {
        case .deadline: .red
        case .milestone: .purple
        case .start: .teal
        case .reminder: .orange
        }
    }
}

struct TaskDate: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var kind: DateKind
    var date: Date
    var note: String = ""
    /// A time of day was chosen (reminders always have one).
    var hasTime = false

    var showsTime: Bool { kind == .reminder || hasTime }
    /// "22/10" or "22/10 15:30".
    var label: String { showsTime ? date.shortTimeLabel : date.shortLabel }
}

extension TaskDate {
    // Tolerant decoding (in an extension so the memberwise initializer stays).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        kind = (try? c.decodeIfPresent(DateKind.self, forKey: .kind)) ?? .deadline
        date = try c.decode(Date.self, forKey: .date)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        hasTime = (try? c.decodeIfPresent(Bool.self, forKey: .hasTime)) ?? false
    }
}

enum HistoryKind: String, Codable {
    case created, moved, completed, reopened, edited, subtask, date, tag, note

    var symbol: String {
        switch self {
        case .created: "plus.circle"
        case .moved: "arrow.right.circle"
        case .completed: "checkmark.circle.fill"
        case .reopened: "arrow.uturn.backward.circle"
        case .edited: "pencil.circle"
        case .subtask: "checklist"
        case .date: "calendar"
        case .tag: "tag"
        case .note: "text.bubble"
        }
    }

    var color: Color {
        switch self {
        case .completed: .green
        case .reopened: .orange
        case .note: .purple
        case .created: .blue
        default: .secondary
        }
    }
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    var kind: HistoryKind
    var text: String
    /// Entries with the same field made within a short time are merged (e.g. while typing).
    var field: String?
}

/// A reusable list of subtasks. Applying it copies the items into a task, so each task
/// can then change its own copy freely.
struct SubtaskPack: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var icon: String = ""
    var items: [String] = []
    /// Tags that add this pack automatically when put on a task.
    var autoTagIDs: [String] = []

    var label: String { icon.isEmpty ? name : "\(icon) \(name)" }

    init(name: String, icon: String = "", items: [String] = [], autoTagIDs: [String] = []) {
        self.name = name
        self.icon = icon
        self.items = items
        self.autoTagIDs = autoTagIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
        autoTagIDs = try c.decodeIfPresent([String].self, forKey: .autoTagIDs) ?? []
    }
}

extension PlannerTask {
    /// Appends a pack's items, skipping ones the task already has (same title).
    /// Returns how many were added.
    @discardableResult
    mutating func apply(_ pack: SubtaskPack) -> Int {
        var added = 0
        for item in pack.items {
            let title = item.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, !subtasks.contains(where: { $0.title == title }) else { continue }
            subtasks.append(Subtask(title: title))
            added += 1
        }
        return added
    }
}

struct FocusSession: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var start: Date
    var minutes: Int
}

/// A file on this Mac or a web address attached to a task.
struct TaskLink: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    /// "https://…" for web links, "file:///…" for files and folders.
    var url: String

    var isFile: Bool { url.hasPrefix("file://") }
    var symbol: String { isFile ? "doc" : "link" }
}

struct Subtask: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var isDone: Bool = false
    /// Optional due day (and time, when `hasTime`).
    var date: Date?
    var hasTime = false

    init(id: String = UUID().uuidString, title: String, isDone: Bool = false, date: Date? = nil, hasTime: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.date = date
        self.hasTime = hasTime
    }

    /// "22/10" or "22/10 15:30".
    var dateLabel: String? { date.map { hasTime ? $0.shortTimeLabel : $0.shortLabel } }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        isDone = (try? c.decodeIfPresent(Bool.self, forKey: .isDone)) ?? false
        date = try? c.decodeIfPresent(Date.self, forKey: .date)
        hasTime = (try? c.decodeIfPresent(Bool.self, forKey: .hasTime)) ?? false
    }

    /// Past its time (or, without one, before today) and not ticked.
    var isOverdue: Bool {
        guard let date, !isDone else { return false }
        return hasTime ? date < Date() : date < Calendar.current.startOfDay(for: Date())
    }
}

struct PlannerTask: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var notes: String = ""
    var columnID: String
    var priorityID: String = "normal"
    var tagIDs: [String] = []
    var dates: [TaskDate] = []
    var subtasks: [Subtask] = []
    /// Optional custom accent color for the card; falls back to the column color.
    var colorHex: String?
    /// Optional card background color.
    var backgroundHex: String?
    /// Position within its column when sorting manually (lower is higher up).
    var order: Double = 0
    /// Set when the task enters a "done" column, cleared when it leaves one.
    var completedAt: Date?
    /// Newest last. Managed by BoardStore.
    var history: [HistoryEntry] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Set while the task is in the trash (Board.trash).
    var deletedAt: Date?
    var recurrence: Recurrence = .none
    /// The rule when `recurrence` is `.custom`.
    var repeatRule: RepeatRule?
    /// The next occurrence has been created (so completing again doesn't make another).
    var recurrenceSpawned = false
    /// Attached files and web links.
    var links: [TaskLink] = []
    /// Turns off reminder and deadline notifications for this task only.
    var notificationsOff = false
    /// How it's going (ids in `Board.flags`); any number, or none.
    var flagIDs: [String] = []
    /// Contacts / collaborators on this task (ids in `Board.contacts`).
    var contactIDs: [String] = []
    /// Finished focus (pomodoro) sessions.
    var focusSessions: [FocusSession] = []

    var focusMinutes: Int { focusSessions.reduce(0) { $0 + $1.minutes } }

    init(title: String, columnID: String) {
        self.title = title
        self.columnID = columnID
    }

    // Tolerant decoding so files written by older/newer versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        columnID = try c.decodeIfPresent(String.self, forKey: .columnID) ?? ""
        priorityID = try c.decodeIfPresent(String.self, forKey: .priorityID) ?? "normal"
        tagIDs = try c.decodeIfPresent([String].self, forKey: .tagIDs) ?? []
        dates = try c.decodeIfPresent([TaskDate].self, forKey: .dates) ?? []
        subtasks = try c.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        backgroundHex = try c.decodeIfPresent(String.self, forKey: .backgroundHex)
        order = try c.decodeIfPresent(Double.self, forKey: .order) ?? 0
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        history = (try? c.decodeIfPresent([HistoryEntry].self, forKey: .history)) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        recurrence = (try? c.decodeIfPresent(Recurrence.self, forKey: .recurrence)) ?? .none
        repeatRule = try? c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule)
        recurrenceSpawned = try c.decodeIfPresent(Bool.self, forKey: .recurrenceSpawned) ?? false
        links = (try? c.decodeIfPresent([TaskLink].self, forKey: .links)) ?? []
        notificationsOff = try c.decodeIfPresent(Bool.self, forKey: .notificationsOff) ?? false
        flagIDs = (try? c.decodeIfPresent([String].self, forKey: .flagIDs)) ?? []
        contactIDs = (try? c.decodeIfPresent([String].self, forKey: .contactIDs)) ?? []
        focusSessions = (try? c.decodeIfPresent([FocusSession].self, forKey: .focusSessions)) ?? []
    }

    var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter(\.isDone).count, subtasks.count)
    }

    /// Dates sorted chronologically.
    var sortedDates: [TaskDate] { dates.sorted { $0.date < $1.date } }

    /// The earliest date that is today or later, or else the latest past one.
    var nextDate: TaskDate? {
        let today = Calendar.current.startOfDay(for: Date())
        return sortedDates.first { $0.date >= today } ?? sortedDates.last
    }
}

struct Board: Codable, Equatable {
    var columns: [BoardColumn]
    var tags: [Tag]
    var tasks: [PlannerTask]
    var sortMode: SortMode = .manual
    /// Fold groups the user has opened ("columnID|groupKey"); everything else starts folded.
    var expandedGroups: [String] = []
    /// Most important first.
    var priorities: [PriorityLevel] = Board.defaultPriorities
    /// Priority given to new tasks.
    var defaultPriorityID: String = "normal"
    /// Deleted tasks, kept for 30 days so they can be restored.
    var trash: [PlannerTask] = []
    var subtaskPacks: [SubtaskPack] = Board.defaultPacks
    /// 今日总结 written in 回顾, keyed "yyyy-MM-dd".
    var dayNotes: [String: String] = [:]
    /// The progress flags users can put on tasks, in menu order.
    var flags: [ProgressFlag] = Board.defaultFlags
    /// Everyone ever added to a task (remembered for picking again).
    var contacts: [Contact] = []
    /// Statuses the widgets show (empty: the widget's own default).
    var widgetColumnIDs: [String] = []
    /// Only tasks with one of these tags appear on the widgets (empty: all tasks).
    var widgetTagIDs: [String] = []

    init(columns: [BoardColumn], tags: [Tag], tasks: [PlannerTask]) {
        self.columns = columns
        self.tags = tags
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        columns = try c.decodeIfPresent([BoardColumn].self, forKey: .columns) ?? Board.defaultColumns
        tags = try c.decodeIfPresent([Tag].self, forKey: .tags) ?? []
        tasks = try c.decodeIfPresent([PlannerTask].self, forKey: .tasks) ?? []
        sortMode = (try? c.decodeIfPresent(SortMode.self, forKey: .sortMode)) ?? .manual
        expandedGroups = try c.decodeIfPresent([String].self, forKey: .expandedGroups) ?? []
        priorities = try c.decodeIfPresent([PriorityLevel].self, forKey: .priorities) ?? Board.defaultPriorities
        if priorities.isEmpty { priorities = Board.defaultPriorities }
        defaultPriorityID = try c.decodeIfPresent(String.self, forKey: .defaultPriorityID) ?? "normal"
        trash = try c.decodeIfPresent([PlannerTask].self, forKey: .trash) ?? []
        subtaskPacks = try c.decodeIfPresent([SubtaskPack].self, forKey: .subtaskPacks) ?? Board.defaultPacks
        dayNotes = try c.decodeIfPresent([String: String].self, forKey: .dayNotes) ?? [:]
        flags = (try? c.decodeIfPresent([ProgressFlag].self, forKey: .flags)) ?? Board.defaultFlags
        contacts = (try? c.decodeIfPresent([Contact].self, forKey: .contacts)) ?? []
        widgetColumnIDs = (try? c.decodeIfPresent([String].self, forKey: .widgetColumnIDs)) ?? []
        widgetTagIDs = (try? c.decodeIfPresent([String].self, forKey: .widgetTagIDs)) ?? []
        if columns.isEmpty { columns = Board.defaultColumns }
    }

    // MARK: Widget filter

    /// The statuses chosen for the widgets, in board order (deleted ones are skipped).
    var widgetColumns: [BoardColumn] {
        columns.filter { widgetColumnIDs.contains($0.id) }
    }

    /// Whether a task passes the widget's tag filter.
    func showsOnWidget(_ task: PlannerTask) -> Bool {
        let chosen = widgetTagIDs.filter { id in tags.contains { $0.id == id } }
        return chosen.isEmpty || task.tagIDs.contains { chosen.contains($0) }
    }

    static let defaultColumns: [BoardColumn] = [
        BoardColumn(id: "todo", name: L("待办"), colorHex: "#5B85F5", icon: "📝"),
        BoardColumn(id: "doing", name: L("进行中"), colorHex: "#F79E33", icon: "🏃"),
        BoardColumn(id: "done", name: L("已完成"), colorHex: "#40B873", isDone: true, icon: "🎉"),
    ]

    static let defaultTags: [Tag] = [
        Tag(name: L("工作"), colorHex: "#5B85F5", icon: "💼"),
        Tag(name: L("学习"), colorHex: "#9B6CF0", icon: "📚"),
        Tag(name: L("生活"), colorHex: "#40B873", icon: "🌱"),
    ]

    static let defaultPriorities: [PriorityLevel] = [
        PriorityLevel(id: "urgent", name: L("紧急"), colorHex: "#E5534B", icon: "🔥"),
        PriorityLevel(id: "high", name: L("高"), colorHex: "#F79E33", icon: "⬆️"),
        PriorityLevel(id: "normal", name: L("中"), colorHex: "#5B85F5"),
        PriorityLevel(id: "low", name: L("低"), colorHex: "#8D99AE", icon: "⬇️"),
    ]

    static let defaultFlags: [ProgressFlag] = [
        ProgressFlag(id: "on-track", name: L("顺利进行"), colorHex: "#40B873", icon: "🟢"),
        ProgressFlag(id: "struggling", name: L("卡住了"), colorHex: "#E5534B", icon: "😣"),
        ProgressFlag(id: "follow-up", name: L("需要跟进"), colorHex: "#F79E33", icon: "🔁"),
        ProgressFlag(id: "need-info", name: L("需要更多信息"), colorHex: "#9B6CF0", icon: "❓"),
        ProgressFlag(id: "waiting", name: L("等待中"), colorHex: "#8D99AE", icon: "⏳"),
    ]

    /// Examples to start from; users can edit or delete them.
    static let defaultPacks: [SubtaskPack] = [
        SubtaskPack(name: L("写作流程"), icon: "📝", items: [L("列提纲"), L("写初稿"), L("修改"), L("校对"), L("定稿")]),
        SubtaskPack(name: L("论文修改"), icon: "📄", items: [L("读审稿意见"), L("列修改清单"), L("改正文"), L("检查引用和格式"), L("写回复信"), L("发给导师")]),
        SubtaskPack(name: L("出行准备"), icon: "✈️", items: [L("订交通"), L("订住宿"), L("查天气"), L("收拾行李")]),
    ]

    /// Packs linked to a tag (added automatically when that tag goes on a task).
    func packs(forTag tagID: String) -> [SubtaskPack] {
        subtaskPacks.filter { $0.autoTagIDs.contains(tagID) }
    }

    static var empty: Board { Board(columns: defaultColumns, tags: defaultTags, tasks: []) }

    func column(_ id: String) -> BoardColumn? { columns.first { $0.id == id } }

    /// The task's priority level (falls back to the default if its level was deleted).
    /// The task's progress flags, in the board's flag order (deleted ones skipped).
    func flags(of task: PlannerTask) -> [ProgressFlag] {
        flags.filter { task.flagIDs.contains($0.id) }
    }

    /// The task's contacts, in the order they were added to it.
    func contacts(of task: PlannerTask) -> [Contact] {
        task.contactIDs.compactMap { id in contacts.first { $0.id == id } }
    }

    func contact(_ id: String) -> Contact? { contacts.first { $0.id == id } }

    /// Contacts, most used first (for picking).
    var contactsByUse: [Contact] {
        var count: [String: Int] = [:]
        for t in tasks { for id in t.contactIDs { count[id, default: 0] += 1 } }
        return contacts.sorted { (count[$0.id] ?? 0, $1.name) > (count[$1.id] ?? 0, $0.name) }
    }

    func priority(of task: PlannerTask) -> PriorityLevel {
        priorities.first { $0.id == task.priorityID }
            ?? priorities.first { $0.id == defaultPriorityID }
            ?? priorities.first
            ?? PriorityLevel(id: "normal", name: L("中"), colorHex: "#5B85F5")
    }

    /// Lower is more important.
    func priorityRank(_ task: PlannerTask) -> Int {
        priorities.firstIndex { $0.id == priority(of: task).id } ?? priorities.count
    }
    func tag(_ id: String) -> Tag? { tags.first { $0.id == id } }

    func tags(for task: PlannerTask) -> [Tag] { task.tagIDs.compactMap(tag) }

    func isDone(_ task: PlannerTask) -> Bool { column(task.columnID)?.isDone ?? false }

    func isOverdue(_ date: TaskDate, of task: PlannerTask) -> Bool {
        date.kind == .deadline && !isDone(task)
            && (date.hasTime ? date.date < Date() : date.date < Calendar.current.startOfDay(for: Date()))
    }

    func accentColor(of task: PlannerTask) -> Color {
        if let hex = task.colorHex { return Color(hex: hex) }
        return column(task.columnID)?.color ?? .gray
    }

    func columnIndex(_ id: String) -> Int? { columns.firstIndex { $0.id == id } }

    func previousColumn(of task: PlannerTask) -> BoardColumn? {
        guard let i = columnIndex(task.columnID), i > 0 else { return nil }
        return columns[i - 1]
    }

    func nextColumn(of task: PlannerTask) -> BoardColumn? {
        guard let i = columnIndex(task.columnID), i < columns.count - 1 else { return nil }
        return columns[i + 1]
    }

    /// Tasks in a column, in display order for the board's sort mode.
    func tasks(in columnID: String, from source: [PlannerTask]? = nil) -> [PlannerTask] {
        let inColumn = (source ?? tasks).filter { $0.columnID == columnID }
        return sorted(inColumn, doneColumn: column(columnID)?.isDone == true, mode: sortMode)
    }

    func sorted(_ list: [PlannerTask], doneColumn: Bool, mode: SortMode) -> [PlannerTask] {
        switch mode {
        case .manual:
            return list.sorted { $0.order != $1.order ? $0.order < $1.order : $0.updatedAt > $1.updatedAt }
        case _ where doneColumn:
            // Automatic modes show the most recently completed first in done columns.
            return list.sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
        case .created:
            return list.sorted { $0.createdAt > $1.createdAt }
        case .date:
            return list.sorted { a, b in
                switch (a.nextDate?.date, b.nextDate?.date) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return priorityRank(a) < priorityRank(b)
                }
            }
        case .priority:
            return list.sorted { a, b in
                let ra = priorityRank(a), rb = priorityRank(b)
                if ra != rb { return ra < rb }
                switch (a.nextDate?.date, b.nextDate?.date) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.updatedAt > b.updatedAt
                }
            }
        }
    }
}

// MARK: - Storage

/// The board is stored as JSON, normally in ~/Library/Application Support/Planner/planner.json.
/// With iCloud sync on, the main copy lives in iCloud Drive (folder "Best Planner") so every
/// Mac on the same Apple ID uses it, and a mirror is kept locally as a safety net.
/// The widget is sandboxed, so paths are built from the real home directory (not its
/// container) and reached through sandbox exceptions for exactly these folders.
enum PlannerStorage {
    #if os(macOS)
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var localDirectory: URL {
        realHome.appendingPathComponent("Library/Application Support/Planner", isDirectory: true)
    }

    static var iCloudDriveRoot: URL {
        realHome.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }
    static var iCloudDirectory: URL { iCloudDriveRoot.appendingPathComponent("Best Planner", isDirectory: true) }

    static var isICloudDriveAvailable: Bool { FileManager.default.fileExists(atPath: iCloudDriveRoot.path) }
    static var usesICloud: Bool { FileManager.default.fileExists(atPath: syncFlagURL.path) && isICloudDriveAvailable }
    #else
    // iPhone: the app reads and writes the iCloud Drive folder the user picked (shared with
    // the Mac). The widget can't open that folder, so the local copy lives in the app group
    // container, where the widget reads it and saves its ticks.
    static let defaultAppGroup = "group.com.bestplanner.app"
    /// SideStore/AltStore rename the app group when they sign the app and list the new
    /// name under ALTAppGroups in Info.plist.
    /// Other installers (iloader…) rename it the same way as the bundle id
    /// ("com.bestplanner.app.TEAMID" → "group.com.bestplanner.app.TEAMID") without saying so.
    static let appGroupContainer: URL? = {
        var candidates: [String] = []
        if var id = Bundle.main.bundleIdentifier {
            if id.hasSuffix(".widget") { id.removeLast(".widget".count) }
            let base = "com.bestplanner.app"
            if id.hasPrefix(base) { candidates.append("group." + base + id.dropFirst(base.count)) }
        }
        candidates += (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]) ?? []
        candidates.append(defaultAppGroup)
        // Only a container we can actually write in: a group we're not entitled to may still
        // give a path. (Checking the container itself isn't enough; try making our folder.)
        let fm = FileManager.default
        for id in candidates {
            guard let url = fm.containerURL(forSecurityApplicationGroupIdentifier: id) else { continue }
            let folder = url.appendingPathComponent("Planner", isDirectory: true)
            if (try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
               fm.isWritableFile(atPath: folder.path) {
                return url
            }
        }
        return nil
    }()
    static var localDirectory: URL {
        let base = appGroupContainer ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Planner", isDirectory: true)
    }
    /// The iCloud Drive folder chosen in the app (security-scoped; set by the app at launch).
    nonisolated(unsafe) static var pickedFolder: URL?
    static var iCloudDirectory: URL { pickedFolder ?? localDirectory }
    static var isICloudDriveAvailable: Bool { pickedFolder != nil }
    static var usesICloud: Bool { pickedFolder != nil }
    /// The local copy (what the widget sees and edits).
    static func mirrorModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: localFileURL.path))?[.modificationDate] as? Date
    }
    static func readMirror() -> Board? { decode(localFileURL) }
    /// What the app last wrote to the local copy. The widget only edits the copy itself,
    /// so comparing the two shows exactly what the widget changed (even across launches).
    static var mirrorBaseURL: URL { localDirectory.appendingPathComponent("planner.base.json") }
    static func readMirrorBase() -> Board? { decode(mirrorBaseURL) }
    /// Refreshes the widget's copy (e.g. after new data arrived from the Mac).
    static func saveMirror(_ board: Board) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(board) else { return }
        try? FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        try? data.write(to: localFileURL, options: .atomic)
        try? data.write(to: mirrorBaseURL, options: .atomic)
    }
    /// The picked folder's file only (no falling back to the local copy).
    static func readCloudFile() -> Board? {
        ensureDownloaded(fileURL)
        return decode(fileURL)
    }
    #endif

    static var localFileURL: URL { localDirectory.appendingPathComponent("planner.json") }
    static var backupDirectory: URL { localDirectory.appendingPathComponent("Backups", isDirectory: true) }
    /// Present when iCloud sync is on (kept locally so both the app and widget can check it).
    private static var syncFlagURL: URL { localDirectory.appendingPathComponent("use-icloud") }

    static var directory: URL { usesICloud ? iCloudDirectory : localDirectory }
    static var fileURL: URL { directory.appendingPathComponent("planner.json") }

    private static func decode(_ url: URL) -> Board? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = readData(url) else { return nil }
        return try? decoder.decode(Board.self, from: data)
    }

    private static func readData(_ url: URL) -> Data? {
        #if os(iOS)
        // Files in iCloud Drive on iOS belong to a file provider: read and write them
        // through a file coordinator so the latest version is used and changes sync.
        if usesICloud, url == fileURL, FileManager.default.fileExists(atPath: url.path) {
            var data: Data?
            var error: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { data = try? Data(contentsOf: $0) }
            return data
        }
        #endif
        return try? Data(contentsOf: url)
    }

    private static func writeData(_ data: Data, to url: URL) throws {
        #if os(iOS)
        if usesICloud, url == fileURL {
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
                do { try data.write(to: target, options: .atomic) } catch { writeError = error }
            }
            if let error = coordinationError ?? writeError { throw error }
            return
        }
        #endif
        try data.write(to: url, options: .atomic)
    }

    static func load() -> Board { read() ?? .empty }

    /// The saved board, or nil when there is a data file but it can't be read right now
    /// (iCloud still downloading, damaged file…). Anything that saves afterwards must use
    /// this, not `load()`: saving the empty fallback would overwrite the real data.
    static func read() -> Board? {
        if usesICloud {
            ensureDownloaded(fileURL)
            if let board = decode(fileURL) { return board }
            // iCloud copy not readable (offline, still downloading…): use the local mirror.
        }
        return decode(localFileURL)
    }

    /// Whether a data file exists at all (a brand-new install has none).
    static var hasData: Bool {
        FileManager.default.fileExists(atPath: fileURL.path) || FileManager.default.fileExists(atPath: localFileURL.path)
    }

    static func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    /// Why the last save didn't reach the data file (nil when it did).
    nonisolated(unsafe) static var lastSaveError: String?

    static func save(_ board: Board) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(board) else { return }
        // The local copy first, so an edit is never lost when the iCloud copy can't be written.
        if usesICloud {
            do {
                try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
                try data.write(to: localFileURL, options: .atomic)
            } catch {
                NSLog("Planner: failed to save the local copy: \(error)")
            }
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeData(data, to: fileURL)
            lastSaveError = nil
            #if os(iOS)
            // Only once iCloud has it: until then the local copy differs from this base, so
            // the next launch (or retry) merges it in again and saves it.
            if usesICloud { try? data.write(to: mirrorBaseURL, options: .atomic) }
            #endif
        } catch {
            lastSaveError = error.localizedDescription
            NSLog("Planner: failed to save board: \(error)")
        }
    }

    /// iCloud may replace a file with a ".name.icloud" placeholder to save space;
    /// ask for it back and wait briefly.
    private static func ensureDownloaded(_ url: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        guard fm.fileExists(atPath: placeholder.path) else { return }
        try? fm.startDownloadingUbiquitousItem(at: url)
        for _ in 0..<50 where !fm.fileExists(atPath: url.path) { Thread.sleep(forTimeInterval: 0.1) }
    }

    // MARK: iCloud switch (app only)

    enum SyncError: LocalizedError {
        case noICloudDrive
        var errorDescription: String? { L("这台 Mac 没有打开 iCloud 云盘。请先在「系统设置 → Apple ID → iCloud → iCloud 云盘」里打开。") }
    }

    /// Turns iCloud sync on or off. Turning it on uses the iCloud copy if another Mac
    /// already put one there, otherwise copies this Mac's data up. Either way the
    /// current local data is backed up first.
    static func setICloud(_ on: Bool) throws {
        let fm = FileManager.default
        backup(force: true)
        if on {
            guard isICloudDriveAvailable else { throw SyncError.noICloudDrive }
            try fm.createDirectory(at: iCloudDirectory, withIntermediateDirectories: true)
            let cloudFile = iCloudDirectory.appendingPathComponent("planner.json")
            ensureDownloaded(cloudFile)
            if !fm.fileExists(atPath: cloudFile.path), fm.fileExists(atPath: localFileURL.path) {
                try fm.copyItem(at: localFileURL, to: cloudFile)
            }
            fm.createFile(atPath: syncFlagURL.path, contents: Data())
        } else {
            // Bring the latest (iCloud) data back to this Mac before switching off.
            if usesICloud, let data = try? Data(contentsOf: fileURL) {
                try data.write(to: localFileURL, options: .atomic)
            }
            try? fm.removeItem(at: syncFlagURL)
        }
    }

    /// Whether an iCloud copy from another Mac exists (to warn before switching on).
    static var iCloudHasData: Bool {
        let cloudFile = iCloudDirectory.appendingPathComponent("planner.json")
        let placeholder = iCloudDirectory.appendingPathComponent(".planner.json.icloud")
        return FileManager.default.fileExists(atPath: cloudFile.path) || FileManager.default.fileExists(atPath: placeholder.path)
    }

    // MARK: Backups

    /// Copies the data file to Backups/planner-YYYY-MM-DD.json once a day (or now when
    /// `force`), keeping the newest 30.
    static func backup(force: Bool = false) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) || fm.fileExists(atPath: localFileURL.path) else { return }
        let source = fm.fileExists(atPath: fileURL.path) ? fileURL : localFileURL
        try? fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let stamp = Date().formatted(.iso8601.year().month().day())
        let name = force ? "planner-\(stamp)-\(Int(Date().timeIntervalSince1970)).json" : "planner-\(stamp).json"
        let target = backupDirectory.appendingPathComponent(name)
        guard force || !fm.fileExists(atPath: target.path) else { return }
        try? fm.copyItem(at: source, to: target)
        let backups = ((try? fm.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { ($0.lastPathComponent) > ($1.lastPathComponent) }
        for old in backups.dropFirst(30) { try? fm.removeItem(at: old) }
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    /// sRGB red, green, blue (0…1), on both macOS and iOS.
    var rgb: (r: Double, g: Double, b: Double)? {
        #if canImport(AppKit)
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (Double(r), Double(g), Double(b))
        #endif
    }

    var hexString: String {
        guard let c = rgb else { return "#888888" }
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.r), byte(c.g), byte(c.b))
    }
}

enum Palette {
    /// Strong colors for statuses, tags and card stripes.
    static let colors = ["#5B85F5", "#F79E33", "#40B873", "#E5534B", "#9B6CF0",
                         "#2BB6C4", "#F2C94C", "#EC6AA8", "#8D99AE", "#6B8E23",
                         "#3B82F6", "#14B8A6", "#84CC16", "#F97316", "#D946EF",
                         "#6366F1", "#B76E79", "#92400E", "#374151", "#111827"]

    /// Soft colors for card backgrounds (plus two dark ones).
    static let pastel = ["#FFF4D6", "#FEF9C3", "#FFEDD5", "#FEE2E2", "#FDE2EF",
                         "#FCE7F3", "#EDE9FE", "#E0E7FF", "#E0F2FE", "#CFFAFE",
                         "#DCFCE7", "#ECFCCB", "#F5F5F4", "#F3F4F6", "#1F2937", "#312E81"]

    static func next(after used: [String]) -> String {
        colors.first { !used.contains($0) } ?? colors.randomElement()!
    }
}

// MARK: - Shared small views

/// Wraps children onto multiple lines, like tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension Color {
    /// Black or white, whichever reads better on top of this color.
    var contrastingText: Color {
        guard let c = rgb else { return .white }
        let luminance = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        return luminance > 0.65 ? .black : .white
    }
}

extension Date {
    var shortLabel: String { formatted(.dateTime.month(.defaultDigits).day()) }
    var shortTimeLabel: String { formatted(.dateTime.month(.defaultDigits).day().hour().minute()) }
    var dayLabel: String { formatted(.dateTime.year().month().day()) }
    var dayTimeLabel: String { formatted(.dateTime.year().month().day().hour().minute()) }
}
