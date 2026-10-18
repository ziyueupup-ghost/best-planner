import SwiftUI

/// Edit (or create) a task. Saves automatically like the Mac editor: a new task is
/// created once it has a title, and edits are merged with changes made elsewhere
/// meanwhile (the widget, the Mac) instead of overwriting them.
struct MobileTaskEditor: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var task: PlannerTask
    /// The stored version this editor last synced with (for merging).
    @State private var base: PlannerTask
    @State private var exists: Bool
    @State private var deleted = false
    @State private var newSubtask = ""
    @State private var newTag = ""
    @State private var packMessage: String?
    @State private var confirmDelete = false
    let isNew: Bool

    init(task: PlannerTask, isNew: Bool) {
        _task = State(initialValue: task)
        _base = State(initialValue: task)
        _exists = State(initialValue: !isNew)
        self.isNew = isNew
    }

    private var board: Board { store.board }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("要做什么？"), text: $task.title, axis: .vertical)
                        .font(.headline)
                    TextField(L("备注"), text: $task.notes, axis: .vertical)
                        .lineLimit(2...8)
                }
                statusSection
                tagSection
                subtaskSection
                dateSection
                if exists {
                    Section {
                        Button(L("删除任务"), role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? L("新建任务") : L("编辑任务"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("完成")) { dismiss() }
                }
                ToolbarItem(placement: .status) {
                    Label(exists ? L("已自动保存") : L("输入标题后自动创建"),
                          systemImage: exists ? "checkmark.circle.fill" : "pencil")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(exists ? Color.green : Color.secondary)
                }
            }
            .alert(L("删除「\(task.title)」？"), isPresented: $confirmDelete) {
                Button(L("移到最近删除"), role: .destructive) {
                    deleted = true
                    store.delete(task.id)
                    dismiss()
                }
                Button(L("取消"), role: .cancel) {}
            } message: {
                Text(L("30 天内可以在 Mac 上的「最近删除」里恢复。"))
            }
        }
        .onChange(of: task) { _, _ in autosave() }
        .onReceive(store.$board) { _ in syncFromStore() }
        .onDisappear {
            addSubtask()
            autosave()
        }
    }

    // MARK: Sections

    private var statusSection: some View {
        Section {
            Picker(L("状态"), selection: $task.columnID) {
                ForEach(board.columns) { c in
                    Text(c.icon.isEmpty ? c.name : "\(c.icon) \(c.name)").tag(c.id)
                }
            }
            Picker(L("优先级"), selection: $task.priorityID) {
                ForEach(board.priorities) { p in Text(p.label).tag(p.id) }
            }
            Picker(L("重复"), selection: $task.recurrence) {
                ForEach(Recurrence.allCases) { r in Text(r.title).tag(r) }
            }
        }
    }

    private var tagSection: some View {
        Section(L("标签")) {
            if store.tags.isEmpty {
                Text(L("还没有标签，在下面新建一个")).foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(store.tags) { tag in
                        let selected = task.tagIDs.contains(tag.id)
                        Button {
                            if selected {
                                task.tagIDs.removeAll { $0 == tag.id }
                            } else {
                                task.tagIDs.append(tag.id)
                                applyPacks(forTag: tag.id)
                            }
                        } label: {
                            TagChip(tag: tag, selected: selected)
                                .environment(\.fontScale, MobileStyle.tagScale)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            HStack {
                TextField(L("新标签"), text: $newTag)
                    .onSubmit(addTag)
                Button(L("添加"), action: addTag)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var subtaskSection: some View {
        Section {
            ForEach($task.subtasks) { $sub in
                HStack(spacing: 10) {
                    Button { sub.isDone.toggle() } label: {
                        Image(systemName: sub.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(sub.isDone ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    TextField(L("子任务"), text: $sub.title, axis: .vertical)
                        .strikethrough(sub.isDone, color: .secondary)
                        .foregroundStyle(sub.isDone ? .secondary : .primary)
                }
            }
            .onDelete { task.subtasks.remove(atOffsets: $0) }
            .onMove { task.subtasks.move(fromOffsets: $0, toOffset: $1) }
            HStack {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField(L("输入子任务，回车添加"), text: $newSubtask)
                    .onSubmit(addSubtask)
                    .submitLabel(.next)
            }
            Menu {
                if board.subtaskPacks.isEmpty {
                    Text(L("还没有子任务包，可以在 Mac 上的设置 →「子任务包」里创建"))
                }
                ForEach(board.subtaskPacks) { pack in
                    Button(L("\(pack.label)（\(pack.items.count) 项）")) { apply(pack) }
                }
            } label: {
                Label(L("应用子任务包"), systemImage: "shippingbox")
            }
            if let packMessage {
                Text(packMessage).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            let done = task.subtasks.filter(\.isDone).count
            Text(task.subtasks.isEmpty ? L("子任务") : L("子任务（\(done)/\(task.subtasks.count)）"))
        } footer: {
            if task.subtasks.count > 1 { Text(L("左滑删除，长按拖动排序。")) }
        }
    }

    private var dateSection: some View {
        Section(L("日期")) {
            ForEach($task.dates) { $d in
                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $d.kind) {
                        ForEach(DateKind.allCases) { k in Label(k.title, systemImage: k.symbol).tag(k) }
                    } label: {
                        Label(d.kind.title, systemImage: d.kind.symbol).foregroundStyle(d.kind.color)
                    }
                    DatePicker(L("时间"), selection: $d.date,
                               displayedComponents: d.kind == .reminder ? [.date, .hourAndMinute] : [.date])
                }
            }
            .onDelete { task.dates.remove(atOffsets: $0) }
            Menu {
                ForEach(DateKind.allCases) { kind in
                    Button { addDate(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                }
            } label: {
                Label(L("添加日期"), systemImage: "calendar.badge.plus")
            }
            if task.dates.contains(where: { $0.kind == .reminder || $0.kind == .deadline }) {
                Toggle(L("这个任务发提醒通知"), isOn: Binding(get: { !task.notificationsOff },
                                                       set: { task.notificationsOff = !$0 }))
            }
        }
    }

    // MARK: Actions

    private func addTag() {
        guard !newTag.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let tag = store.addTag(named: newTag)
        if !task.tagIDs.contains(tag.id) {
            task.tagIDs.append(tag.id)
            applyPacks(forTag: tag.id)
        }
        newTag = ""
    }

    private func apply(_ pack: SubtaskPack) {
        let added = task.apply(pack)
        packMessage = added > 0 ? L("已添加「\(pack.name)」的 \(added) 个子任务") : L("「\(pack.name)」的子任务都已经有了")
    }

    /// Adding a tag also adds the subtask packs linked to it.
    private func applyPacks(forTag tagID: String) {
        let packs = board.packs(forTag: tagID)
        guard !packs.isEmpty else { return }
        let added = packs.reduce(0) { $0 + task.apply($1) }
        if added > 0 {
            packMessage = L("已按标签自动添加 \(added) 个子任务（\(packs.map(\.name).joined(separator: "、"))）")
        }
    }

    private func addSubtask() {
        let title = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        task.subtasks.append(Subtask(title: title))
        newSubtask = ""
    }

    private func addDate(_ kind: DateKind) {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .hour, for: Date())?.start ?? Date()
        let date = kind == .reminder ? (cal.date(byAdding: .hour, value: 1, to: start) ?? Date())
                                     : (cal.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date())
        task.dates.append(TaskDate(kind: kind, date: date))
    }

    private func autosave() {
        var t = task
        t.title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deleted, !t.title.isEmpty else { return }
        if exists {
            store.update(t, base: base)
        } else if store.tasks.contains(where: { $0.id == t.id }) == false {
            store.add(t)
            exists = true
        }
        if let stored = store.task(t.id) { base = stored }
    }

    /// The task changed elsewhere while this editor is open: bring those changes in,
    /// keeping whatever was edited here.
    private func syncFromStore() {
        guard exists, !deleted, let stored = store.task(task.id), !stored.sameEditableContent(as: base) else { return }
        let merged = PlannerTask.merge(base: base, mine: task, theirs: stored)
        base = stored
        if !merged.sameEditableContent(as: task) { task = merged }
    }
}
