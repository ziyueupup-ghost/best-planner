import SwiftUI

private struct ColumnRef: Identifiable { let id: String }

/// Multi-select state shared by the board, its columns and cards.
final class TaskSelection: ObservableObject {
    @Published var ids: Set<String> = []
    /// In select mode a plain click selects; otherwise use ⌘-click.
    @Published var mode = false

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }

    func clear() {
        ids.removeAll()
        mode = false
    }
}

struct BoardView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.fontScale) private var fontScale
    @AppStorage(FontScale.storageKey) private var storedFontScale = 1.0
    @State private var editing: PlannerTask?
    @State private var creatingIn: ColumnRef?
    @State private var showWidgetFilter = false
    @State private var showSettings = false
    @State private var search = ""
    @State private var tagFilter: String?
    @State private var showTrash = false
    @State private var showStats = false
    @State private var confirmICloud = false
    /// Achievements already announced (comma-separated ids).
    @AppStorage("seenAchievements") private var seenAchievements = ""
    @State private var newAchievement: Achievement?
    @State private var iCloudError: String?
    @StateObject private var selection = TaskSelection()
    @Environment(\.undoManager) private var undoManager
    /// "board" or "agenda".
    @AppStorage("viewMode") private var viewMode = "board"
    @State private var confirmBatchDelete = false
    /// Widths while a column edge is being dragged (committed to the store on release).
    @State private var liveWidths: [String: CGFloat] = [:]

    private var minColumnWidth: CGFloat { 150 * fontScale }

    /// Custom-width columns keep their width; the rest share what's left of the window.
    private func columnWidths(total: CGFloat) -> [String: CGFloat] {
        let cols = store.columns
        var fixed: [String: CGFloat] = [:]
        for c in cols {
            if let live = liveWidths[c.id] { fixed[c.id] = live }
            else if let w = c.width { fixed[c.id] = max(minColumnWidth, CGFloat(w) * fontScale) }
        }
        let autoCount = CGFloat(cols.count - fixed.count)
        let available = total - 32 - 14 * CGFloat(max(cols.count - 1, 0)) - fixed.values.reduce(0, +)
        let autoWidth = autoCount > 0 ? max(180 * fontScale, available / autoCount) : 0
        return Dictionary(uniqueKeysWithValues: cols.map { ($0.id, fixed[$0.id] ?? autoWidth) })
    }

    var body: some View {
        withEvents(withSheets(decorated))
    }

    /// Board / agenda / review content with its overlays and the multi-select alert.
    private var mainArea: some View {
        Group {
            if viewMode == "agenda" {
                AgendaView(visibleIDs: Set(filtered.map(\.id)), onEdit: { editing = $0 })
            } else if viewMode == "review" {
                ReviewView(onEdit: { editing = $0 })
            } else {
                boardColumns
            }
        }
        .environmentObject(selection)
        .onAppear {
            store.undoManager = undoManager
            // Opened by clicking a notification before the window existed.
            if let id = ReminderScheduler.shared.pendingOpenTaskID {
                ReminderScheduler.shared.pendingOpenTaskID = nil
                editing = store.task(id)
            }
        }
        .onChange(of: undoManager) { _, manager in store.undoManager = manager }
        .overlay(alignment: .bottom) {
            if !liveSelection.isEmpty {
                batchBar
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: liveSelection.isEmpty)
        .overlay(alignment: .top) { achievementBanner }
        .onChange(of: store.board.tasks) { _, _ in announceAchievements() }
        .onAppear { announceAchievements() }
        .overlay(alignment: .bottomLeading) {
            FocusBar()
                .padding(14)
                .padding(.bottom, liveSelection.isEmpty ? 0 : 56)
        }
        .onExitCommand { selection.clear() }
        .alert(L("删除选中的 \(liveSelection.count) 个任务？"), isPresented: $confirmBatchDelete) {
            Button(L("移到最近删除"), role: .destructive) {
                withAnimation(.snappy) { store.deleteTasks(liveSelection) }
                selection.clear()
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("30 天内可以在「最近删除」里恢复。"))
        }
    }

    /// Window background, search field and toolbar.
    private var decorated: some View {
        mainArea
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $search, placement: .toolbar, prompt: L("搜索任务"))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker(L("视图"), selection: $viewMode) {
                    Label(L("看板"), systemImage: "rectangle.split.3x1").tag("board")
                    Label(L("日程"), systemImage: "calendar.day.timeline.left").tag("agenda")
                    Label(L("回顾"), systemImage: "calendar").tag("review")
                }
                .pickerStyle(.segmented)
                .help(L("看板：按状态分列；日程：按日期看没完成的任务；回顾：日历看每天完成了什么，还有成就"))
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showWidgetFilter.toggle()
                } label: {
                    Label(L("小组件"), systemImage: "square.grid.2x2")
                }
                .help(L("选择桌面小组件显示哪些状态和标签"))
                .popover(isPresented: $showWidgetFilter, arrowEdge: .bottom) {
                    WidgetFilterView().environmentObject(store)
                }
                Menu {
                    LanguageChoices()
                } label: {
                    Label(L("语言 / Language"), systemImage: "globe")
                }
                .help(L("切换语言：中文 / English"))
                Toggle(isOn: Binding(get: { selection.mode }, set: { on in
                    if on { selection.mode = true } else { selection.clear() }
                })) {
                    Label(L("选择"), systemImage: selection.mode ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .help(L("多选任务：打开后单击卡片选择（不打开也可以 ⌘+单击），然后一起移动或删除"))
                fontSizeMenu
                sortMenu
                tagFilterMenu

                Button {
                    showSettings = true
                } label: {
                    Label(L("管理状态和标签"), systemImage: "slider.horizontal.3")
                }
                .help(L("管理状态和标签 (⌘,)"))

                Button {
                    showStats = true
                } label: {
                    Label(L("统计"), systemImage: "chart.bar.xaxis")
                }
                .help(L("统计：完成数量、专注时间、按标签"))

                Button {
                    showTrash = true
                } label: {
                    Label(L("最近删除"), systemImage: store.board.trash.isEmpty ? "trash" : "trash.fill")
                }
                .help(L("最近删除（\(store.board.trash.count) 项，保留 30 天，可以恢复）"))

                Button {
                    creatingIn = store.columns.first.map { ColumnRef(id: $0.id) }
                } label: {
                    Label(L("新建任务"), systemImage: "plus")
                }
                .help(L("新建任务 (⌘N)"))
            }
        }
    }

    private func withSheets(_ content: some View) -> some View {
        content
        .sheet(item: $creatingIn) { ref in
            TaskEditor(task: newTask(in: ref.id), isNew: true)
                .environmentObject(store)
                .appFontSize()
        }
        .sheet(item: $editing) { task in
            TaskEditor(task: task, isNew: false)
                .environmentObject(store)
                .appFontSize()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(columns: store.columns, tags: store.tags,
                         priorities: store.board.priorities, defaultPriorityID: store.board.defaultPriorityID,
                         packs: store.board.subtaskPacks, flags: store.board.flags, contacts: store.board.contacts)
                .environmentObject(store)
                .appFontSize()
        }
        .sheet(isPresented: $showStats) {
            StatsView()
                .environmentObject(store)
                .appFontSize()
        }
        .sheet(isPresented: $showTrash) {
            TrashView()
                .environmentObject(store)
                .appFontSize()
        }
    }

    private func withEvents(_ content: some View) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: .newTaskRequested)) { _ in
            creatingIn = store.columns.first.map { ColumnRef(id: $0.id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsRequested)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .trashRequested)) { _ in
            showTrash = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .iCloudToggleRequested)) { _ in
            confirmICloud = true
        }
        .alert(store.usesICloud ? L("关闭 iCloud 云盘同步？") : L("使用 iCloud 云盘同步？"), isPresented: $confirmICloud) {
            Button(store.usesICloud ? L("关闭同步") : L("开始同步")) {
                do { try store.setICloudSync(!store.usesICloud) } catch { iCloudError = error.localizedDescription }
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            if store.usesICloud {
                Text(L("数据会从 iCloud 云盘拷回这台 Mac，之后只保存在本机，不再和其他 Mac 同步。"))
            } else if PlannerStorage.iCloudHasData {
                Text(L("iCloud 云盘里已经有另一台 Mac 的数据，开启后这台 Mac 会改用 iCloud 里的数据。这台 Mac 现在的数据会先自动备份（菜单「打开备份文件夹」里能找到）。"))
            } else {
                Text(L("数据会放到 iCloud 云盘的「Best Planner」文件夹，登录同一个 Apple ID 的 Mac 都能用同一份。本机也会保留一份镜像。注意：两台 Mac 同时修改时，以最后保存的为准。"))
            }
        }
        .alert(L("没能切换同步"), isPresented: Binding(get: { iCloudError != nil }, set: { if !$0 { iCloudError = nil } })) {
            Button(L("好")) {}
        } message: {
            Text(iCloudError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTaskRequested)) { note in
            guard let id = note.object as? String, let task = store.task(id) else { return }
            ReminderScheduler.shared.pendingOpenTaskID = nil
            if editing == nil && creatingIn == nil {
                editing = task
            } else {
                // Another editor is closing; open this one once it's gone.
                editing = nil
                creatingIn = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editing = store.task(id) }
            }
        }
    }

    /// The kanban columns side by side (custom widths, resize handles).
    private var boardColumns: some View {
        GeometryReader { geo in
            let widths = columnWidths(total: geo.size.width)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(store.columns) { column in
                        let width = widths[column.id] ?? 260
                        ColumnView(
                            column: column,
                            tasks: store.board.tasks(in: column.id, from: filtered),
                            forceExpand: !search.trimmingCharacters(in: .whitespaces).isEmpty,
                            onAdd: { creatingIn = ColumnRef(id: column.id) },
                            onEdit: { editing = $0 }
                        )
                        .frame(width: width)
                        .overlay(alignment: .trailing) {
                            ColumnResizeHandle(
                                width: width,
                                minWidth: minColumnWidth,
                                isCustom: column.width != nil,
                                onLive: { liveWidths[column.id] = $0 },
                                onCommit: { w in
                                    store.setColumnWidth(column.id, Double(w / fontScale))
                                    liveWidths[column.id] = nil
                                },
                                onReset: {
                                    liveWidths[column.id] = nil
                                    withAnimation(.snappy) { store.setColumnWidth(column.id, nil) }
                                }
                            )
                            .offset(x: 10)
                        }
                    }
                }
                .padding(16)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
        }
    }

    /// Selected ids that still exist (tasks may have been deleted elsewhere).
    private var liveSelection: Set<String> {
        selection.ids.intersection(store.tasks.map(\.id))
    }

    /// Full labels when there's room, icons only in a narrow window.
    private var batchBar: some View {
        ViewThatFits(in: .horizontal) {
            batchBarContent.labelStyle(.titleAndIcon)
            batchBarContent.labelStyle(.iconOnly)
        }
        .padding(.horizontal, 12)
    }

    private var batchBarContent: some View {
        let ids = liveSelection
        return HStack(spacing: 10) {
            Text(L("已选 \(ids.count) 项"))
                .scaledFont(.callout, weight: .semibold)
            Divider().frame(height: 18)
            Menu {
                ForEach(store.columns) { c in
                    Button(c.icon.isEmpty ? c.name : "\(c.icon) \(c.name)") {
                        withAnimation(.snappy) { store.moveTasks(ids, to: c.id) }
                    }
                }
            } label: {
                Label(L("移到状态"), systemImage: "arrow.right.square")
            }
            .fixedSize()
            Button { withAnimation(.snappy) { store.shiftTasks(ids, by: -1) } } label: { Label(L("上移"), systemImage: "arrow.up") }
            Button { withAnimation(.snappy) { store.shiftTasks(ids, by: 1) } } label: { Label(L("下移"), systemImage: "arrow.down") }
            Button { withAnimation(.snappy) { store.moveTasksToEdge(ids, top: true) } } label: { Label(L("最上"), systemImage: "arrow.up.to.line") }
            Button { withAnimation(.snappy) { store.moveTasksToEdge(ids, top: false) } } label: { Label(L("最下"), systemImage: "arrow.down.to.line") }
            Divider().frame(height: 18)
            Button(role: .destructive) { confirmBatchDelete = true } label: { Label(L("删除…"), systemImage: "trash") }
            Button(L("完成")) { selection.clear() }
                .keyboardShortcut(.defaultAction)
        }
        .fixedSize()
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
    }

    @ViewBuilder
    private var achievementBanner: some View {
            if let a = newAchievement {
                HStack(spacing: 10) {
                    Text(a.icon).font(.system(size: 30 * fontScale))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("解锁成就：\(a.title)")).scaledFont(.headline)
                        Text(a.detail).scaledFont(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.6), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { viewMode = "review"; newAchievement = nil }
            }
    }

    /// Shows a banner for achievements unlocked since last time. The first run only
    /// records what's already unlocked, without announcing it.
    private func announceAchievements() {
        let unlocked = store.board.review().achievements.filter(\.isUnlocked)
        let ids = Set(unlocked.map(\.id))
        let firstRun = seenAchievements.isEmpty
        let seen = Set(seenAchievements.split(separator: ",").map(String.init))
        let fresh = unlocked.filter { !seen.contains($0.id) }
        seenAchievements = (seen.union(ids).isEmpty ? ["-"] : Array(seen.union(ids))).sorted().joined(separator: ",")
        guard !firstRun, let first = fresh.first else { return }
        withAnimation(.snappy) { newAchievement = first }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation(.snappy) { if newAchievement?.id == first.id { newAchievement = nil } }
        }
    }

    private func newTask(in columnID: String) -> PlannerTask {
        var t = PlannerTask(title: "", columnID: columnID)
        t.priorityID = store.board.defaultPriorityID
        return t
    }

    private var fontSizeMenu: some View {
        Menu {
            ForEach(FontScale.presets, id: \.value) { preset in
                Button {
                    storedFontScale = preset.value
                } label: {
                    let title = "\(preset.title)  \(Int(preset.value * 100))%"
                    if abs(storedFontScale - preset.value) < 0.001 { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
            Divider()
            Button(L("放大字体")) { storedFontScale = FontScale.clamped(storedFontScale + FontScale.step) }
            Button(L("缩小字体")) { storedFontScale = FontScale.clamped(storedFontScale - FontScale.step) }
        } label: {
            Label(L("字体大小"), systemImage: "textformat.size")
        }
        .help(L("字体大小：\(FontScale.title(for: storedFontScale))（⌘+ 放大，⌘- 缩小，⌘0 还原）"))
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortMode.allCases) { mode in
                Button {
                    withAnimation(.snappy) { store.setSortMode(mode) }
                } label: {
                    if store.board.sortMode == mode { Label(mode.title, systemImage: "checkmark") } else { Text(mode.title) }
                }
            }
        } label: {
            Label(L("排序"), systemImage: "arrow.up.arrow.down")
        }
        .help(L("任务排序方式：\(store.board.sortMode.title)"))
    }

    private var tagFilterMenu: some View {
        Menu {
            Button {
                tagFilter = nil
            } label: {
                if tagFilter == nil { Label(L("全部标签"), systemImage: "checkmark") } else { Text(L("全部标签")) }
            }
            if !store.tags.isEmpty { Divider() }
            ForEach(store.tags) { tag in
                Button {
                    tagFilter = tag.id
                } label: {
                    if tagFilter == tag.id { Label(tag.name, systemImage: "checkmark") } else { Text(tag.name) }
                }
            }
        } label: {
            Label(tagFilter.flatMap { store.board.tag($0)?.name } ?? L("标签"),
                  systemImage: tagFilter == nil ? "tag" : "tag.fill")
        }
        .help(L("按标签筛选"))
    }

    private var filtered: [PlannerTask] {
        var result = store.tasks
        if let tagFilter { result = result.filter { $0.tagIDs.contains(tagFilter) } }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            result = result.filter { task in
                task.title.localizedCaseInsensitiveContains(q)
                    || task.notes.localizedCaseInsensitiveContains(q)
                    || task.subtasks.contains { $0.title.localizedCaseInsensitiveContains(q) }
                    || store.board.tags(for: task).contains { $0.name.localizedCaseInsensitiveContains(q) }
                    || store.board.flags(of: task).contains { $0.name.localizedCaseInsensitiveContains(q) }
                    || store.board.contacts(of: task).contains {
                        $0.name.localizedCaseInsensitiveContains(q) || $0.email.localizedCaseInsensitiveContains(q)
                    }
            }
        }
        return result
    }
}

struct ColumnView: View {
    @EnvironmentObject private var store: BoardStore
    let column: BoardColumn
    let tasks: [PlannerTask]
    /// While searching, every fold group is shown open so results aren't hidden.
    var forceExpand = false
    let onAdd: () -> Void
    let onEdit: (PlannerTask) -> Void
    @State private var isTargeted = false
    @State private var confirmClear = false
    @EnvironmentObject fileprivate var selection: TaskSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if column.icon.isEmpty {
                    Circle()
                        .fill(column.color)
                        .frame(width: 10, height: 10)
                } else {
                    Text(column.icon)
                        .scaledFont(.title3)
                }
                Text(column.name)
                    .scaledFont(.headline)
                    .lineLimit(1)
                if column.isDone {
                    Image(systemName: "checkmark.seal.fill")
                        .scaledFont(.caption)
                        .foregroundStyle(column.color)
                        .help(L("完成列"))
                }
                Text("\(tasks.count)")
                    .scaledFont(.caption, monospacedDigit: true)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(column.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(column.color)
                Spacer()
                foldMenu
                Button(action: onAdd) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(L("在「\(column.name)」中添加任务"))
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if column.foldMode == .off {
                        ForEach(tasks) { card($0) }
                    } else {
                        let groups = store.board.foldGroups(tasks, in: column)
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            let open = forceExpand || store.board.isGroupExpanded(column.id, group.key)
                            FoldGroupHeader(
                                group: group,
                                expanded: open,
                                isFirst: index == 0,
                                isLast: index == groups.count - 1,
                                toggle: { withAnimation(.snappy) { store.toggleGroup(column.id, group.key) } },
                                moveBefore: { dragged in
                                    withAnimation(.snappy) { store.moveGroup(dragged, before: group.key, in: column.id) }
                                },
                                shift: { offset in
                                    withAnimation(.snappy) { store.shiftGroup(group.key, by: offset, in: column.id) }
                                },
                                moveToEdge: { top in
                                    withAnimation(.snappy) {
                                        store.moveGroup(group.key, before: top ? groups.first?.key : nil, in: column.id)
                                    }
                                }
                            )
                            if open {
                                // Keyed by group too: a card moving to another group (a tag just
                                // added) must be rebuilt, or the lazy stack keeps showing its old content.
                                ForEach(group.tasks) { card($0).id("\(group.key)|\($0.id)") }
                            }
                        }
                    }
                    if tasks.isEmpty {
                        Text(L("拖动任务到这里"))
                            .scaledFont(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .padding(2)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(column.color.opacity(isTargeted ? 0.12 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(column.color.opacity(isTargeted ? 0.6 : 0), lineWidth: 2)
        )
        .alert(L("清空「\(column.name)」？"), isPresented: $confirmClear) {
            Button(L("移到最近删除"), role: .destructive) {
                withAnimation(.snappy) { store.clearColumn(column.id) }
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("这一列的 \(store.board.tasks(in: column.id).count) 个任务会移到「最近删除」，30 天内可以恢复。"))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first else { return false }
            let ids = TaskDrag.ids(item)
            withAnimation(.snappy) {
                if ids.count > 1 {
                    if store.board.sortMode == .manual {
                        store.placeTasks(Set(ids), before: nil, in: column.id)
                    } else {
                        store.moveTasks(Set(ids), to: column.id)
                    }
                } else if store.board.sortMode == .manual {
                    store.place(item, before: nil, in: column.id)
                } else {
                    store.move(item, to: column.id)
                }
            }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

extension ColumnView {
    fileprivate func card(_ task: PlannerTask) -> some View {
        TaskCard(task: task, onEdit: { onEdit(task) })
            .draggable(dragPayload(task))
    }

    /// Dragging a selected card carries the whole selection along.
    fileprivate func dragPayload(_ task: PlannerTask) -> String {
        guard selection.ids.contains(task.id), selection.ids.count > 1 else { return task.id }
        return TaskDrag.payload(store.board.orderedIDs(selection.ids))
    }

    fileprivate var foldMenu: some View {
        Menu {
            Picker(L("折叠方式"), selection: Binding(
                get: { column.foldMode },
                set: { mode in withAnimation(.snappy) { store.setFoldMode(column.id, mode) } }
            )) {
                ForEach(FoldMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
            if column.foldMode != .off {
                Divider()
                Button(L("全部展开")) { withAnimation(.snappy) { store.setAllGroups(column.id, expanded: true) } }
                Button(L("全部折叠")) { withAnimation(.snappy) { store.setAllGroups(column.id, expanded: false) } }
                if column.foldMode != .all {
                    Button(L("恢复默认分组顺序")) { withAnimation(.snappy) { store.resetGroupOrder(column.id) } }
                        .disabled(column.groupOrder.isEmpty)
                }
            }
            Divider()
            Button(L("清空这一列…")) { confirmClear = true }
                .disabled(store.board.tasks(in: column.id).isEmpty)
            Divider()
            Picker(L("列宽（也可以拖动列的右边缘）"), selection: Binding(
                get: { column.width ?? 0 },
                set: { w in withAnimation(.snappy) { store.setColumnWidth(column.id, w == 0 ? nil : w) } }
            )) {
                ForEach(ColumnWidthPreset.all, id: \.value) { preset in
                    Text(preset.title).tag(preset.value)
                }
                if let w = column.width, !ColumnWidthPreset.all.contains(where: { $0.value == w }) {
                    Text(L("自定义（\(Int(w))）")).tag(w)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: column.foldMode == .off ? "rectangle.compress.vertical" : column.foldMode.symbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(column.foldMode == .off ? Color.secondary : column.color)
        .help(L("列选项：折叠方式、列宽、清空这一列"))
    }
}

/// Clickable header of a fold group: chevron, label, count. Drag it onto another
/// group's header (or use the right-click menu) to change the group order.
struct FoldGroupHeader: View {
    let group: FoldGroup
    let expanded: Bool
    let isFirst: Bool
    let isLast: Bool
    let toggle: () -> Void
    /// Called with the dragged group's key when it's dropped on this header.
    let moveBefore: (String) -> Void
    let shift: (Int) -> Void
    let moveToEdge: (_ top: Bool) -> Void
    @State private var hovering = false
    @State private var dropTargeted = false

    static let dragPrefix = "fold-group:"

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .scaledFont(.caption, weight: .bold)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                switch group.header {
                case .tag(let tag):
                    TagChip(tag: tag)
                case .priority(let level):
                    PriorityMark(level: level)
                    Text(level.name)
                        .scaledFont(.callout, weight: .medium)
                case .text(let title, let symbol, let color):
                    Image(systemName: symbol)
                        .scaledFont(.caption)
                        .foregroundStyle(color)
                    Text(title)
                        .scaledFont(.callout, weight: .medium)
                }
                Text("\(group.tasks.count)")
                    .scaledFont(.caption, monospacedDigit: true)
                    .foregroundStyle(.secondary)
                Spacer()
                if hovering {
                    Image(systemName: "line.3.horizontal")
                        .scaledFont(.caption)
                        .foregroundStyle(.tertiary)
                        .help(L("拖动可以调整分组顺序"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(expanded ? L("点击折叠，拖动调整顺序") : L("点击展开，拖动调整顺序"))
        .draggable(Self.dragPrefix + group.key)
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first, item.hasPrefix(Self.dragPrefix) else { return false }
            moveBefore(String(item.dropFirst(Self.dragPrefix.count)))
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay(alignment: .top) {
            if dropTargeted {
                Capsule().fill(Color.accentColor).frame(height: 3).offset(y: -5)
            }
        }
        .contextMenu {
            Button(L("上移")) { shift(-1) }.disabled(isFirst)
            Button(L("下移")) { shift(1) }.disabled(isLast)
            Divider()
            Button(L("移到最上面")) { moveToEdge(true) }.disabled(isFirst)
            Button(L("移到最下面")) { moveToEdge(false) }.disabled(isLast)
        }
    }
}

struct TaskCard: View {
    @EnvironmentObject private var store: BoardStore
    let task: PlannerTask
    let onEdit: () -> Void
    @State private var hovering = false
    @State private var showSubtasks = false
    @State private var dropTargeted = false
    @State private var confirmDelete = false
    @EnvironmentObject private var selection: TaskSelection

    private var board: Board { store.board }
    private var isSelected: Bool { selection.ids.contains(task.id) }
    private var done: Bool { board.isDone(task) }

    private var cardBackground: Color {
        task.backgroundHex.map(Color.init(hex:)) ?? Color(nsColor: .controlBackgroundColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                PriorityMark(level: board.priority(of: task))
                Text(task.title)
                    .scaledFont(.body, weight: .medium)
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? .secondary : .primary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }

            if !task.notes.isEmpty {
                Text(task.notes)
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            let tags = board.tags(for: task)
            let flags = board.flags(of: task)
            if !tags.isEmpty || !flags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(flags) { FlagChip(flag: $0) }
                    ForEach(tags) { TagChip(tag: $0, small: true) }
                }
            }
            let people = board.contacts(of: task)
            if !people.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "person.2").foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(people) { ContactNameButton(contact: $0) }
                    }
                }
                .scaledFont(.caption)
            }

            if !task.dates.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(task.sortedDates.prefix(3)) { d in
                        DateLine(date: d, overdue: board.isOverdue(d, of: task))
                    }
                    if task.notificationsOff, task.dates.contains(where: { $0.kind == .reminder || $0.kind == .deadline }) {
                        Label(L("不发通知"), systemImage: "bell.slash")
                            .scaledFont(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if task.dates.count > 3 {
                        Text(L("还有 \(task.dates.count - 3) 个日期"))
                            .scaledFont(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let m = task.nextAutoMove, let target = board.column(m.columnID) {
                Label(L("\(m.label) → \(target.name)"), systemImage: "forward.fill")
                    .scaledFont(.caption)
                    .foregroundStyle(target.color)
                    .help(L("到时间会自动移到「\(target.name)」"))
            }

            if !task.links.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(task.links.prefix(3)) { link in
                        Button {
                            if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
                        } label: {
                            Label(link.title, systemImage: link.isFile ? "paperclip" : "link")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .help(L("打开「\(link.title)」"))
                    }
                    if task.links.count > 3 {
                        Text(L("还有 \(task.links.count - 3) 个附件"))
                            .foregroundStyle(.tertiary)
                    }
                }
                .scaledFont(.caption)
            }

            if task.focusMinutes > 0 {
                Text(L("🍅 专注 \(task.focusMinutes) 分钟"))
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }

            if task.recurrence != .none {
                Label(task.repeatTitle, systemImage: "repeat")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .help(L("重复任务：完成后会自动生成下一次"))
            }

            if done, let completed = task.completedAt {
                Label(L("完成于 \(completed.dayLabel)"), systemImage: "checkmark.circle.fill")
                    .scaledFont(.caption)
                    .foregroundStyle(.green)
            }

            if !task.subtasks.isEmpty {
                subtaskSection
            }

            HStack(spacing: 6) {
                Spacer()
                moveButton("chevron.left", target: board.previousColumn(of: task)) {
                    withAnimation(.snappy) { store.moveLeft(task) }
                }
                moveButton("chevron.right", target: board.nextColumn(of: task)) {
                    withAnimation(.snappy) { store.moveRight(task) }
                }
            }
        }
        .padding(10)
        .padding(.leading, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // With a custom background, base text on black/white; .secondary etc. derive from it.
        .foregroundStyle(task.backgroundHex.map { Color(hex: $0).contrastingText } ?? Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardBackground)
                .shadow(color: .black.opacity(hovering ? 0.15 : 0.06), radius: hovering ? 5 : 2, y: 1)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10, style: .continuous)
                .fill(board.accentColor(of: task))
                .frame(width: 4)
        }
        .overlay(alignment: .top) {
            // Insertion marker while another card is dragged over this one.
            if dropTargeted {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .offset(y: -6)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "checkmark.circle.fill")
                            .scaledFont(.title3)
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 6, y: -6)
                    }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onEdit)
        .onTapGesture {
            if selection.mode || NSEvent.modifierFlags.contains(.command) { selection.toggle(task.id) }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first else { return false }
            let ids = TaskDrag.ids(item)
            guard !ids.contains(task.id) else { return false }
            withAnimation(.snappy) {
                if ids.count > 1 {
                    store.placeTasks(Set(ids), before: task.id, in: task.columnID)
                } else {
                    store.place(item, before: task.id, in: task.columnID)
                }
            }
            return true
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button(L("编辑…"), action: onEdit)
            Button(isSelected ? L("取消选择") : L("选择（多选）")) { selection.toggle(task.id) }
            FocusMenu(task: task, inContextMenu: true)
            Menu(L("进展")) {
                ForEach(board.flags) { f in
                    Button {
                        store.toggleFlag(task.id, f.id)
                    } label: {
                        if task.flagIDs.contains(f.id) { Label(f.label, systemImage: "checkmark") } else { Text(f.label) }
                    }
                }
                if !task.flagIDs.isEmpty {
                    Divider()
                    Button(L("清除进展标记")) { store.toggleFlag(task.id, nil) }
                }
            }
            let mailable = board.contacts(of: task).filter { !$0.email.trimmingCharacters(in: .whitespaces).isEmpty }
            if !mailable.isEmpty {
                Menu(L("发邮件")) {
                    ForEach(mailable) { c in
                        Button("\(c.name) <\(c.email)>") { MailComposer.compose(to: [c.email], subject: task.title) }
                    }
                    if mailable.count > 1 {
                        Divider()
                        Button(L("发给全部（\(mailable.count) 人）")) {
                            MailComposer.compose(to: mailable.map(\.email), subject: task.title)
                        }
                    }
                }
            }
            OpenLinksMenu(links: task.links)
            Divider()
            Button(L("复制任务")) { duplicate(resetChecks: false) }
            if task.subtasks.contains(where: \.isDone) {
                Button(L("复制任务（子任务清空勾选）")) { duplicate(resetChecks: true) }
            }
            Divider()
            Button(L("移到最上面")) { withAnimation(.snappy) { store.moveToTop(task.id) } }
            Button(L("移到最下面")) { withAnimation(.snappy) { store.moveToBottom(task.id) } }
            Menu(L("移动到")) {
                ForEach(board.columns) { c in
                    Button(c.name) { store.move(task.id, to: c.id) }
                        .disabled(c.id == task.columnID)
                }
            }
            Divider()
            Button(L("删除…"), role: .destructive) { confirmDelete = true }
        }
        .alert(L("删除「\(task.title)」？"), isPresented: $confirmDelete) {
            Button(L("移到最近删除"), role: .destructive) { withAnimation(.snappy) { store.delete(task.id) } }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("30 天内可以在「最近删除」里恢复。"))
        }
    }

    /// The copy goes right above this task and its editor opens for quick changes.
    private func duplicate(resetChecks: Bool) {
        var copy: PlannerTask?
        withAnimation(.snappy) { copy = store.duplicate(task.id, resetChecks: resetChecks) }
        if let copy { NotificationCenter.default.post(name: .openTaskRequested, object: copy.id) }
    }

    private var subtaskSection: some View {
        let p = task.subtaskProgress
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy) { showSubtasks.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .scaledFont(.caption2, weight: .bold)
                        .rotationEffect(.degrees(showSubtasks ? 90 : 0))
                    Image(systemName: "checklist")
                        .scaledFont(.caption)
                    Text("\(p.done)/\(p.total)")
                        .scaledFont(.caption, monospacedDigit: true)
                    ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                        .progressViewStyle(.linear)
                        .tint(board.accentColor(of: task))
                        .frame(maxWidth: 90)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSubtasks {
                ForEach(task.subtasks) { sub in
                    Button {
                        store.toggleSubtask(task.id, sub.id)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: sub.isDone ? "checkmark.square.fill" : "square")
                                .foregroundStyle(sub.isDone ? board.accentColor(of: task) : .secondary)
                            Text(sub.title)
                                .scaledFont(.callout)
                                .strikethrough(sub.isDone, color: .secondary)
                                .foregroundStyle(sub.isDone ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if let label = sub.dateLabel {
                                Text(label)
                                    .scaledFont(.caption2, monospacedDigit: true)
                                    .foregroundStyle(sub.isOverdue ? Color.red : Color.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 14)
                }
            }
        }
    }

    private func moveButton(_ symbol: String, target: BoardColumn?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(.caption, weight: .bold)
                .frame(width: 22, height: 20)
                .background(Color.primary.opacity(hovering && target != nil ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(target != nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
        .disabled(target == nil)
        .help(target.map { L("移到「\($0.name)」") } ?? "")
    }
}

struct DateLine: View {
    let date: TaskDate
    let overdue: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: date.kind.symbol)
                .foregroundStyle(overdue ? .red : date.kind.color)
            Text(date.kind.title)
                .foregroundStyle(.secondary)
            Text(date.showsTime
                 ? date.date.formatted(.dateTime.month(.defaultDigits).day().hour().minute())
                 : date.date.formatted(.dateTime.year(.twoDigits).month(.defaultDigits).day()))
                .foregroundStyle(overdue ? .red : .primary)
                .fontWeight(overdue ? .semibold : .regular)
            if !date.note.isEmpty {
                Text(date.note)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if overdue {
                Text(L("已过期")).foregroundStyle(.red)
            }
        }
        .scaledFont(.caption)
    }
}

/// The marker in front of a task title: the priority's emoji, or a colored dot.
struct PriorityMark: View {
    let level: PriorityLevel

    var body: some View {
        Group {
            if level.icon.isEmpty {
                Circle()
                    .fill(level.color)
                    .frame(width: 7, height: 7)
            } else {
                Text(level.icon)
                    .scaledFont(.caption)
            }
        }
        .help(L("优先级：\(level.name)"))
    }
}

/// Drag handle on a column's right edge. Double-click returns to automatic width.
struct ColumnResizeHandle: View {
    let width: CGFloat
    let minWidth: CGFloat
    let isCustom: Bool
    let onLive: (CGFloat) -> Void
    let onCommit: (CGFloat) -> Void
    let onReset: () -> Void
    @State private var startWidth: CGFloat?
    @State private var hovering = false

    var body: some View {
        Capsule()
            .fill(Color.accentColor.opacity(startWidth != nil ? 0.8 : hovering ? 0.5 : 0))
            .frame(width: 3)
            .padding(.vertical, 20)
            .frame(width: 12)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                // Leaving the board while hovering the edge would otherwise keep the ↔ cursor.
                if hovering { NSCursor.pop(); hovering = false }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = startWidth ?? width
                        if startWidth == nil { startWidth = start }
                        onLive(max(minWidth, start + value.translation.width))
                    }
                    .onEnded { value in
                        let start = startWidth ?? width
                        startWidth = nil
                        onCommit(max(minWidth, start + value.translation.width))
                    }
            )
            .onTapGesture(count: 2, perform: onReset)
            .help(isCustom ? L("拖动调整宽度，双击恢复自动宽度") : L("拖动调整这一列的宽度"))
    }
}

enum ColumnWidthPreset {
    /// 0 means automatic (share the window evenly).
    static let all: [(value: Double, title: String)] = [
        (0, L("自动")), (160, L("很窄")), (220, L("窄")), (300, L("标准")), (380, L("宽")), (480, L("很宽")),
    ]
}
