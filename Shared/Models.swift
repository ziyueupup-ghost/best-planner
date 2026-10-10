import AppKit
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
        case .manual: "手动排序（拖动调整）"
        case .priority: "按优先级"
        case .date: "按日期"
        case .created: "按创建时间"
        }
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
        case .deadline: "截止"
        case .milestone: "里程碑"
        case .start: "开始"
        case .reminder: "提醒"
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
    /// The next occurrence has been created (so completing again doesn't make another).
    var recurrenceSpawned = false
    /// Attached files and web links.
    var links: [TaskLink] = []
    /// Turns off reminder and deadline notifications for this task only.
    var notificationsOff = false
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
        recurrenceSpawned = try c.decodeIfPresent(Bool.self, forKey: .recurrenceSpawned) ?? false
        links = (try? c.decodeIfPresent([TaskLink].self, forKey: .links)) ?? []
        notificationsOff = try c.decodeIfPresent(Bool.self, forKey: .notificationsOff) ?? false
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
        if columns.isEmpty { columns = Board.defaultColumns }
    }

    static let defaultColumns: [BoardColumn] = [
        BoardColumn(id: "todo", name: "待办", colorHex: "#5B85F5", icon: "📝"),
        BoardColumn(id: "doing", name: "进行中", colorHex: "#F79E33", icon: "🏃"),
        BoardColumn(id: "done", name: "已完成", colorHex: "#40B873", isDone: true, icon: "🎉"),
    ]

    static let defaultTags: [Tag] = [
        Tag(name: "工作", colorHex: "#5B85F5", icon: "💼"),
        Tag(name: "学习", colorHex: "#9B6CF0", icon: "📚"),
        Tag(name: "生活", colorHex: "#40B873", icon: "🌱"),
    ]

    static let defaultPriorities: [PriorityLevel] = [
        PriorityLevel(id: "urgent", name: "紧急", colorHex: "#E5534B", icon: "🔥"),
        PriorityLevel(id: "high", name: "高", colorHex: "#F79E33", icon: "⬆️"),
        PriorityLevel(id: "normal", name: "中", colorHex: "#5B85F5"),
        PriorityLevel(id: "low", name: "低", colorHex: "#8D99AE", icon: "⬇️"),
    ]

    /// Examples to start from; users can edit or delete them.
    static let defaultPacks: [SubtaskPack] = [
        SubtaskPack(name: "写作流程", icon: "📝", items: ["列提纲", "写初稿", "修改", "校对", "定稿"]),
        SubtaskPack(name: "论文修改", icon: "📄", items: ["读审稿意见", "列修改清单", "改正文", "检查引用和格式", "写回复信", "发给导师"]),
        SubtaskPack(name: "出行准备", icon: "✈️", items: ["订交通", "订住宿", "查天气", "收拾行李"]),
    ]

    /// Packs linked to a tag (added automatically when that tag goes on a task).
    func packs(forTag tagID: String) -> [SubtaskPack] {
        subtaskPacks.filter { $0.autoTagIDs.contains(tagID) }
    }

    static var empty: Board { Board(columns: defaultColumns, tags: defaultTags, tasks: []) }

    func column(_ id: String) -> BoardColumn? { columns.first { $0.id == id } }

    /// The task's priority level (falls back to the default if its level was deleted).
    func priority(of task: PlannerTask) -> PriorityLevel {
        priorities.first { $0.id == task.priorityID }
            ?? priorities.first { $0.id == defaultPriorityID }
            ?? priorities.first
            ?? PriorityLevel(id: "normal", name: "中", colorHex: "#5B85F5")
    }

    /// Lower is more important.
    func priorityRank(_ task: PlannerTask) -> Int {
        priorities.firstIndex { $0.id == priority(of: task).id } ?? priorities.count
    }
    func tag(_ id: String) -> Tag? { tags.first { $0.id == id } }

    func tags(for task: PlannerTask) -> [Tag] { task.tagIDs.compactMap(tag) }

    func isDone(_ task: PlannerTask) -> Bool { column(task.columnID)?.isDone ?? false }

    func isOverdue(_ date: TaskDate, of task: PlannerTask) -> Bool {
        date.kind == .deadline && !isDone(task) && date.date < Calendar.current.startOfDay(for: Date())
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
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var localDirectory: URL {
        realHome.appendingPathComponent("Library/Application Support/Planner", isDirectory: true)
    }
    static var localFileURL: URL { localDirectory.appendingPathComponent("planner.json") }
    static var backupDirectory: URL { localDirectory.appendingPathComponent("Backups", isDirectory: true) }

    static var iCloudDriveRoot: URL {
        realHome.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }
    static var iCloudDirectory: URL { iCloudDriveRoot.appendingPathComponent("Best Planner", isDirectory: true) }
    /// Present when iCloud sync is on (kept locally so both the app and widget can check it).
    private static var syncFlagURL: URL { localDirectory.appendingPathComponent("use-icloud") }

    static var isICloudDriveAvailable: Bool { FileManager.default.fileExists(atPath: iCloudDriveRoot.path) }
    static var usesICloud: Bool { FileManager.default.fileExists(atPath: syncFlagURL.path) && isICloudDriveAvailable }

    static var directory: URL { usesICloud ? iCloudDirectory : localDirectory }
    static var fileURL: URL { directory.appendingPathComponent("planner.json") }

    private static func decode(_ url: URL) -> Board? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Board.self, from: data)
    }

    static func load() -> Board {
        if usesICloud {
            ensureDownloaded(fileURL)
            if let board = decode(fileURL) { return board }
            // iCloud copy not readable (offline, still downloading…): use the local mirror.
        }
        return decode(localFileURL) ?? .empty
    }

    static func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    static func save(_ board: Board) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(board)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            if usesICloud {
                try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
                try data.write(to: localFileURL, options: .atomic)
            }
        } catch {
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
        var errorDescription: String? { "这台 Mac 没有打开 iCloud 云盘。请先在「系统设置 → Apple ID → iCloud → iCloud 云盘」里打开。" }
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

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#888888" }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
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
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luminance > 0.65 ? .black : .white
    }
}

extension Date {
    var shortLabel: String { formatted(.dateTime.month(.defaultDigits).day()) }
    var dayLabel: String { formatted(.dateTime.year().month().day()) }
    var dayTimeLabel: String { formatted(.dateTime.year().month().day().hour().minute()) }
}
