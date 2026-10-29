import SwiftUI

/// Edits a task with autosave: every change is written to the store immediately.
/// A new task is created as soon as it has a title.
struct TaskEditor: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fontScale) private var fontScale
    @State private var task: PlannerTask
    /// The stored version this editor last synced with (for merging, see Shared/Merge.swift).
    @State private var base: PlannerTask
    @State private var newSubtask = ""
    @State private var newTag = ""
    @State private var newNote = ""
    @State private var packMessage: String?
    @State private var confirmDelete = false
    @State private var exists: Bool
    @State private var deleted = false
    let isNew: Bool

    init(task: PlannerTask, isNew: Bool) {
        _task = State(initialValue: task)
        _base = State(initialValue: task)
        _exists = State(initialValue: !isNew)
        self.isNew = isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? L("新建任务") : L("编辑任务"))
                .scaledFont(.title2, weight: .bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 4)

            Form {
                basicSection
                tagSection
                flagSection
                ContactSection(contactIDs: $task.contactIDs)
                dateSection
                autoMoveSection
                subtaskSection
                LinksSection(links: $task.links)
                historySection
            }
            .formStyle(.grouped)

            HStack {
                if exists {
                    FocusMenu(task: task)
                        .fixedSize()
                    Menu(L("复制")) {
                        Button(L("复制任务")) { duplicate(resetChecks: false) }
                        Button(L("复制任务（子任务清空勾选）")) { duplicate(resetChecks: true) }
                    }
                    .fixedSize()
                    .help(L("复制一份放在这个任务下面"))
                    Button(L("删除任务"), role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Label(exists ? L("已自动保存") : L("输入标题后自动创建"),
                      systemImage: exists ? "checkmark.circle.fill" : "pencil")
                    .scaledFont(.caption)
                    .foregroundStyle(exists ? Color.green : Color.secondary)
                Button(L("完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 8)
        }
        .frame(width: FontScale.sheetSize(width: 520, height: 640, scale: fontScale).width,
               height: FontScale.sheetSize(width: 520, height: 640, scale: fontScale).height)
        .onChange(of: task) { _, _ in autosave() }
        .onReceive(store.$board) { _ in syncFromStore() }
        .onDisappear {
            addSubtask()
            autosave()
            if exists, !deleted { store.addNote(task.id, newNote) }
        }
        .onExitCommand { dismiss() }
        .alert(L("删除「\(task.title)」？"), isPresented: $confirmDelete) {
            Button(L("移到最近删除"), role: .destructive) {
                deleted = true
                store.delete(task.id)
                dismiss()
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("30 天内可以在「最近删除」里恢复。"))
        }
    }

    // MARK: Sections

    private var basicSection: some View {
        Section {
            TextField(L("标题"), text: $task.title, prompt: Text(L("要做什么？")))
            VStack(alignment: .leading, spacing: 4) {
                Text(L("备注"))
                TextEditor(text: $task.notes)
                    .scaledFont(.body)
                    .scrollContentBackground(.hidden)
                    .frame(height: 110 * fontScale)
                    .padding(4)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topLeading) {
                        if task.notes.isEmpty {
                            Text(L("可选（内容多时可以往下滚动）"))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .allowsHitTesting(false)
                        }
                    }
            }
            Picker(L("状态"), selection: $task.columnID) {
                ForEach(store.columns) { c in
                    Text(c.icon.isEmpty ? c.name : "\(c.icon) \(c.name)").tag(c.id)
                }
            }
            let levels = store.board.priorities
            if levels.count <= 5 {
                Picker(L("优先级"), selection: $task.priorityID) {
                    ForEach(levels) { Text($0.label).tag($0.id) }
                }
                .pickerStyle(.segmented)
            } else {
                Picker(L("优先级"), selection: $task.priorityID) {
                    ForEach(levels) { Text($0.label).tag($0.id) }
                }
            }
            Picker(selection: $task.recurrence) {
                ForEach(Recurrence.allCases) { Text($0.title).tag($0) }
            } label: {
                Label(L("重复"), systemImage: "repeat")
            }
            .help(L("完成后自动生成下一次，日期按周期往后推"))
            .onChange(of: task.recurrence) { _, value in
                if value == .custom, task.repeatRule == nil { task.repeatRule = .starting(on: task.dates.map(\.date).min() ?? Date()) }
            }
            if task.recurrence == .custom {
                RepeatRuleEditor(rule: Binding(get: { task.repeatRule ?? .starting() }, set: { task.repeatRule = $0 }))
            }
            optionalColorRow(L("左侧色条颜色"), hex: $task.colorHex, fallback: Palette.colors[4], palette: Palette.colors)
            optionalColorRow(L("卡片背景颜色"), hex: $task.backgroundHex, fallback: "#FFF4D6", palette: Palette.pastel + Palette.colors)
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
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                TextField(L("新标签"), text: $newTag, prompt: Text(L("输入标签名，回车添加")))
                    .onSubmit(addTag)
                Button(L("添加"), action: addTag)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// Planned moves: "at this date/time, move to that status".
    private var autoMoveSection: some View {
        Section {
            ForEach($task.autoMoves) { $m in
                HStack(spacing: 8) {
                    Image(systemName: "forward.fill").foregroundStyle(.secondary).frame(width: 18)
                    DatePicker("", selection: $m.date, displayedComponents: m.hasTime ? [.date, .hourAndMinute] : [.date])
                        .labelsHidden()
                    Toggle(L("时间"), isOn: $m.hasTime)
                        .toggleStyle(.checkbox)
                    Text(L("移到"))
                    Picker("", selection: $m.columnID) {
                        ForEach(store.columns) { c in Text(c.icon.isEmpty ? c.name : "\(c.icon) \(c.name)").tag(c.id) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 150)
                    Spacer(minLength: 0)
                    Button {
                        task.autoMoves.removeAll { $0.id == m.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                let cal = Calendar.current
                let tomorrow9 = cal.date(bySettingHour: 9, minute: 0, second: 0,
                                         of: cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()) ?? Date()
                // Default target: the status after the current one.
                let cols = store.columns
                let i = cols.firstIndex { $0.id == task.columnID } ?? 0
                let target = cols[min(i + 1, cols.count - 1)].id
                task.autoMoves.append(AutoMove(date: tomorrow9, columnID: target))
            } label: {
                Label(L("添加自动移动"), systemImage: "plus")
            }
        } header: {
            Text(L("自动移动"))
        } footer: {
            Text(L("到了设定的日期 / 时间，任务会自动移到选定的状态（比如从待办到进行中）。软件开着时每半分钟检查一次；那时没开的话，下次打开时补上。"))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// How the task is going: any number of flags, or none.
    private var flagSection: some View {
        Section {
            FlowLayout(spacing: 6) {
                ForEach(store.board.flags) { f in
                    let on = task.flagIDs.contains(f.id)
                    Button {
                        if on { task.flagIDs.removeAll { $0 == f.id } } else { task.flagIDs.append(f.id) }
                    } label: {
                        FlagChip(flag: f)
                            .saturation(on ? 1 : 0)
                            .opacity(on ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text(L("进展"))
        } footer: {
            Text(L("可以选多个，也可以不选；会显示在卡片上。在设置 →「进展」里自定义。"))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dateSection: some View {
        Section {
            ForEach($task.dates) { $d in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: d.kind.symbol)
                            .foregroundStyle(d.kind.color)
                            .frame(width: 18)
                        Picker("", selection: $d.kind) {
                            ForEach(DateKind.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        DatePicker("", selection: $d.date,
                                   displayedComponents: d.showsTime ? [.date, .hourAndMinute] : [.date])
                            .labelsHidden()
                        if d.kind != .reminder {
                            Toggle(L("时间"), isOn: $d.hasTime)
                                .toggleStyle(.checkbox)
                                .help(L("设定具体几点几分（到点通知；不设就是当天早上 9 点通知）"))
                        }
                        Spacer()
                        Button {
                            task.dates.removeAll { $0.id == d.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L("删除这个日期"))
                    }
                    TextField(L("说明"), text: $d.note, prompt: Text(L("说明（可选），例如：初稿完成")))
                        .labelsHidden()
                        .padding(.leading, 26)
                }
            }
            if task.dates.contains(where: { $0.kind == .reminder || $0.kind == .deadline }) {
                Toggle(isOn: Binding(get: { !task.notificationsOff }, set: { task.notificationsOff = !$0 })) {
                    Label(task.notificationsOff ? L("这个任务不发通知") : L("到时间发通知"),
                          systemImage: task.notificationsOff ? "bell.slash" : "bell")
                }
                .help(L("关掉后，这个任务的「提醒」和「截止」都不会弹出通知（只影响这一个任务）"))
            }
            Menu {
                ForEach(DateKind.allCases) { kind in
                    Button {
                        task.dates.append(TaskDate(kind: kind, date: kind == .reminder ? Self.nextFullHour : Calendar.current.startOfDay(for: Date())))
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            } label: {
                Label(L("添加日期"), systemImage: "calendar.badge.plus")
            }
            .fixedSize()
        } header: {
            Text(L("日期"))
        } footer: {
            Text(L("可以添加多个：截止、里程碑、开始、提醒。「提醒」到点会弹出通知，「截止」当天早上 9 点通知；截止日期过了会标红。"))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var subtaskSection: some View {
        Section {
            ForEach($task.subtasks) { $sub in
                let i = task.subtasks.firstIndex { $0.id == sub.id } ?? 0
                HStack {
                    VStack(spacing: 0) {
                        Button { task.subtasks.swapAt(i, i - 1) } label: {
                            Image(systemName: "chevron.up").scaledFont(.caption2, weight: .bold)
                        }
                        .disabled(i == 0)
                        .help(L("上移"))
                        Button { task.subtasks.swapAt(i, i + 1) } label: {
                            Image(systemName: "chevron.down").scaledFont(.caption2, weight: .bold)
                        }
                        .disabled(i >= task.subtasks.count - 1)
                        .help(L("下移"))
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 16)
                    Toggle("", isOn: $sub.isDone)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    TextField("", text: $sub.title)
                        .labelsHidden()
                        .strikethrough(sub.isDone)
                    SubtaskDateButton(date: $sub.date, hasTime: $sub.hasTime, isDone: sub.isDone)
                    Button {
                        task.subtasks.removeAll { $0.id == sub.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField(L("新子任务"), text: $newSubtask, prompt: Text(L("添加子任务，回车确认")))
                    .labelsHidden()
                    .onSubmit(addSubtask)
            }
            HStack {
                Menu {
                    if store.board.subtaskPacks.isEmpty {
                        Text(L("还没有子任务包，可以在设置 →「子任务包」里创建"))
                    }
                    ForEach(store.board.subtaskPacks) { pack in
                        Button(L("\(pack.label)（\(pack.items.count) 项）")) { apply(pack) }
                    }
                    Divider()
                    Button(L("把当前子任务存为新的子任务包")) {
                        store.addPack(name: task.title, items: task.subtasks.map(\.title))
                        packMessage = L("已存为子任务包「\(task.title.isEmpty ? L("新子任务包") : task.title)」")
                    }
                    .disabled(task.subtasks.isEmpty)
                } label: {
                    Label(L("应用子任务包"), systemImage: "shippingbox")
                }
                .fixedSize()
                if let packMessage {
                    Text(packMessage)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            let p = task.subtaskProgress
            Text(p.total == 0 ? L("子任务") : L("子任务 \(p.done)/\(p.total)"))
        }
    }

    private var historySection: some View {
        Section {
            if let stored = store.task(task.id) {
                if store.board.isDone(stored) {
                    DatePicker(selection: Binding(
                        get: { stored.completedAt ?? Date() },
                        set: { store.setCompletedAt(task.id, $0) }
                    ), displayedComponents: [.date, .hourAndMinute]) {
                        Label(L("完成日期"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                HStack {
                    Image(systemName: "text.bubble").foregroundStyle(.secondary)
                    TextField(L("添加记录"), text: $newNote, prompt: Text(L("写一条记录，回车添加（例如：和老师讨论过）")))
                        .labelsHidden()
                        .onSubmit {
                            store.addNote(task.id, newNote)
                            newNote = ""
                        }
                }
                ForEach(stored.history.reversed()) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: entry.kind.symbol)
                            .foregroundStyle(entry.kind.color)
                            .frame(width: 16)
                        Text(entry.text)
                            .foregroundStyle(entry.kind == .note ? .primary : .secondary)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        Text(entry.date.dayTimeLabel)
                            .scaledFont(.caption, monospacedDigit: true)
                            .foregroundStyle(.tertiary)
                    }
                    .scaledFont(.callout)
                    .contextMenu {
                        Button(L("删除这条记录"), role: .destructive) {
                            store.deleteHistoryEntry(task.id, entry.id)
                        }
                    }
                }
            } else {
                Text(L("创建任务后会自动记录历史")).foregroundStyle(.secondary)
            }
        } header: {
            Text(L("完成与历史"))
        } footer: {
            Text(L("移动状态、完成、修改内容、勾选子任务都会自动记录。右键可以删除某条记录。"))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func optionalColorRow(_ title: String, hex: Binding<String?>, fallback: String, palette: [String]) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { hex.wrappedValue != nil },
                set: { hex.wrappedValue = $0 ? (hex.wrappedValue ?? fallback) : nil }
            ))
            Spacer()
            if hex.wrappedValue != nil {
                ColorSwatchPicker(hex: Binding(
                    get: { hex.wrappedValue ?? fallback },
                    set: { hex.wrappedValue = $0 }
                ), palette: palette)
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
        let packs = store.board.packs(forTag: tagID)
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

    /// Default time for a new 提醒: the next full hour.
    static var nextFullHour: Date {
        let cal = Calendar.current
        let hour = cal.dateInterval(of: .hour, for: Date())?.start ?? Date()
        return cal.date(byAdding: .hour, value: 1, to: hour) ?? Date()
    }

    /// Saves pending edits first so the copy includes them, then switches to the copy's editor.
    private func duplicate(resetChecks: Bool) {
        addSubtask()
        autosave()
        guard let copy = store.duplicate(task.id, resetChecks: resetChecks) else { return }
        dismiss()
        NotificationCenter.default.post(name: .openTaskRequested, object: copy.id)
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

    /// The task changed elsewhere while this editor is open (widget, agenda, another Mac):
    /// bring those changes in, keeping whatever was edited here.
    private func syncFromStore() {
        guard exists, !deleted, let stored = store.task(task.id), !stored.sameEditableContent(as: base) else { return }
        let merged = PlannerTask.merge(base: base, mine: task, theirs: stored)
        base = stored
        if !merged.sameEditableContent(as: task) { task = merged }
    }
}
