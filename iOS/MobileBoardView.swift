import SwiftUI

/// The board on a phone: one status column at a time (switch at the top), its tasks as a
/// list folded into the same groups as on the Mac. Tap a task to edit it; swipe to move
/// it to the previous/next status or delete it.
struct MobileBoardView: View {
    @EnvironmentObject private var store: BoardStore
    @AppStorage("mobileColumnID") private var columnID = ""
    @State private var search = ""
    @State private var editing: EditorTarget?
    @State private var showSettings = false

    private var board: Board { store.board }
    private var column: BoardColumn? { board.column(columnID) ?? board.columns.first }

    private var filtered: [PlannerTask] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return board.tasks }
        return board.tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(q)
                || task.notes.localizedCaseInsensitiveContains(q)
                || task.subtasks.contains { $0.title.localizedCaseInsensitiveContains(q) }
                || board.tags(for: task).contains { $0.name.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                columnPicker
                if let error = store.saveError {
                    Label(L("没能保存到 iCloud，会自动重试：\(error)"), systemImage: "exclamationmark.icloud.fill")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red)
                }
                if let column {
                    taskList(column)
                }
            }
            .navigationTitle("Best Planner")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: Text(L("搜索任务")))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(L("设置"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let column { editing = .new(column.id) }
                    } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                        .accessibilityLabel(L("新建任务"))
                }
            }
        }
        .sheet(item: $editing) { target in
            switch target {
            case .new(let columnID):
                MobileTaskEditor(task: newTask(in: columnID), isNew: true)
            case .existing(let id):
                if let task = store.task(id) { MobileTaskEditor(task: task, isNew: false) }
            }
        }
        .sheet(isPresented: $showSettings) { MobileSettingsView() }
        .onReceive(NotificationCenter.default.publisher(for: .openTaskRequested)) { note in
            if let id = note.object as? String, store.task(id) != nil { editing = .existing(id) }
        }
        .onAppear {
            if let id = ReminderScheduler.shared.pendingOpenTaskID {
                ReminderScheduler.shared.pendingOpenTaskID = nil
                editing = .existing(id)
            }
        }
    }

    private func newTask(in columnID: String) -> PlannerTask {
        var t = PlannerTask(title: "", columnID: columnID)
        t.priorityID = board.defaultPriorityID
        return t
    }

    // MARK: Columns

    private var columnPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(board.columns) { c in
                        let selected = c.id == column?.id
                        Button {
                            withAnimation(.snappy) { columnID = c.id }
                        } label: {
                            HStack(spacing: 5) {
                                if !c.icon.isEmpty { Text(c.icon) }
                                Text(c.name).fontWeight(.semibold)
                                Text("\(board.tasks(in: c.id, from: filtered).count)")
                                    .font(.caption.monospacedDigit())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(c.color.opacity(selected ? 0.3 : 0.15), in: Capsule())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                            .background(selected ? c.color.opacity(0.22) : Color(.secondarySystemBackground), in: Capsule())
                            .overlay(Capsule().strokeBorder(selected ? c.color : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .id(c.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onAppear { if let id = column?.id { proxy.scrollTo(id, anchor: .center) } }
        }
    }

    // MARK: Tasks

    @ViewBuilder
    private func taskList(_ column: BoardColumn) -> some View {
        let tasks = board.tasks(in: column.id, from: filtered)
        List {
            if tasks.isEmpty {
                Text(search.isEmpty ? L("这里还没有任务，点右上角 ＋ 新建。") : L("没有找到匹配的任务"))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else if column.foldMode == .off {
                ForEach(tasks) { row($0) }
            } else {
                ForEach(board.foldGroups(tasks, in: column)) { group in
                    let open = !search.isEmpty || board.isGroupExpanded(column.id, group.key)
                    Section {
                        // The group title is an ordinary first row: in a section header,
                        // its tap handling also caught taps on the cards below.
                        Button {
                            withAnimation(.snappy) { store.toggleGroup(column.id, group.key) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(open ? 90 : 0))
                                groupHeader(group)
                                Text("\(group.tasks.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if open {
                            ForEach(group.tasks) { row($0).id("\(group.key)|\($0.id)") }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        // Folded groups sit close together instead of a full section gap apart.
        .listSectionSpacing(10)
    }

    @ViewBuilder
    private func groupHeader(_ group: FoldGroup) -> some View {
        switch group.header {
        case .text(let title, let symbol, let color):
            Label(title, systemImage: symbol).foregroundStyle(color).font(.headline)
        case .tag(let tag):
            TagChip(tag: tag).environment(\.fontScale, MobileStyle.tagScale)
        case .priority(let level):
            Text(level.label).foregroundStyle(level.color).font(.headline)
        }
    }

    private func row(_ task: PlannerTask) -> some View {
        MobileTaskRow(task: task) { editing = .existing(task.id) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let next = board.nextColumn(of: task) {
                    Button { withAnimation { store.moveRight(task) } } label: {
                        Label(next.name, systemImage: "arrow.right")
                    }
                    .tint(next.color)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { withAnimation { store.delete(task.id) } } label: {
                    Label(L("删除"), systemImage: "trash")
                }
                if let previous = board.previousColumn(of: task) {
                    Button { withAnimation { store.moveLeft(task) } } label: {
                        Label(previous.name, systemImage: "arrow.left")
                    }
                    .tint(previous.color)
                }
            }
    }
}

enum EditorTarget: Identifiable {
    case new(String)
    case existing(String)

    var id: String {
        switch self {
        case .new(let column): "new-\(column)"
        case .existing(let id): id
        }
    }
}

/// One task in the list: done circle, title, tags, dates, and its subtasks (tick them
/// right here; expand with the arrow).
struct MobileTaskRow: View {
    @EnvironmentObject private var store: BoardStore
    let task: PlannerTask
    let onEdit: () -> Void
    @State private var showSubtasks = false

    private var board: Board { store.board }
    private var done: Bool { board.isDone(task) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                withAnimation(.snappy) { store.toggleDone(task.id) }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Color.green : board.accentColor(of: task))
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    let level = board.priority(of: task)
                    if level.icon.isEmpty {
                        Circle().fill(level.color).frame(width: 7, height: 7)
                    } else {
                        Text(level.icon).font(.caption)
                    }
                    Text(task.title)
                        .font(.title3.weight(.medium))
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? .secondary : .primary)
                        .lineLimit(3)
                }
                if !task.notes.isEmpty {
                    Text(task.notes).font(.body).foregroundStyle(.secondary).lineLimit(2)
                }
                let tags = board.tags(for: task)
                if !tags.isEmpty || !task.dates.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(tags) { TagChip(tag: $0).environment(\.fontScale, MobileStyle.tagScale) }
                            ForEach(task.dates.sorted { $0.date < $1.date }) { d in
                                let overdue = board.isOverdue(d, of: task)
                                Label(d.label, systemImage: d.kind.symbol)
                                    .font(.subheadline)
                                    .foregroundStyle(overdue ? .red : d.kind.color)
                            }
                        }
                    }
                }
                if !task.subtasks.isEmpty { subtasks }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
        }
        .padding(.vertical, 3)
        .overlay(alignment: .leading) {
            if let hex = task.colorHex {
                Rectangle().fill(Color(hex: hex)).frame(width: 3).offset(x: -16)
            }
        }
    }

    private var subtasks: some View {
        let doneCount = task.subtasks.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { showSubtasks.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(showSubtasks ? 90 : 0))
                    Image(systemName: "checklist").font(.subheadline)
                    Text("\(doneCount)/\(task.subtasks.count)").font(.subheadline.monospacedDigit())
                    ProgressView(value: Double(doneCount), total: Double(task.subtasks.count))
                        .frame(width: 70)
                        .tint(board.accentColor(of: task))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .tint(.secondary)
            if showSubtasks {
                ForEach(task.subtasks) { sub in
                    Button {
                        store.toggleSubtask(task.id, sub.id)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: sub.isDone ? "checkmark.square.fill" : "square")
                                .foregroundStyle(sub.isDone ? Color.green : Color.secondary)
                            Text(sub.title)
                                .font(.body)
                                .strikethrough(sub.isDone, color: .secondary)
                                .foregroundStyle(sub.isDone ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                            if let label = sub.dateLabel {
                                Text(label)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(sub.isOverdue ? Color.red : Color.secondary)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .tint(.primary)
                }
            }
        }
    }
}

enum MobileStyle {
    /// Tag chips are drawn at caption size (shared with the Mac); on the phone they read
    /// better a good deal larger.
    static let tagScale: CGFloat = 1.35
}
