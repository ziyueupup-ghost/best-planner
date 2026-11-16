import SwiftUI

/// 日程: on the left one long list of plans, a heading per day — earlier days that still
/// have one, today, the next days, later planned days — each with its tasks and subtasks in
/// the order to do them: drag (or ↑↓) to reorder, tick to finish, move to another day, × to
/// take one off; what's left on an earlier day moves to today in one click. On the right the
/// agenda: open tasks and dated subtasks by date (overdue, today, the next days, later, no
/// date), each with ＋ to put it on today (right-click ＋ for another day) or to drag onto
/// any day's heading, and a field for a new task; a task's subtasks can be picked one by one.
struct TodayView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.fontScale) private var fontScale
    let onEdit: (PlannerTask) -> Void

    @State private var search = ""
    /// A new task typed in the agenda panel (added to today's plan).
    @State private var newTask = ""
    /// Tasks whose subtasks are shown in the pick list.
    @State private var expanded: Set<String> = []
    /// The pick panel on the right: its width (drag the divider) and whether it's folded away.
    @AppStorage("todayPickWidth") private var pickWidth = 320.0
    @AppStorage("todayPickHidden") private var pickHidden = false
    /// How many days ahead the agenda lists one by one.
    @AppStorage("agendaDays") private var agendaDays = 7
    @State private var dragStartWidth: Double?
    /// A day further ahead picked with 其他日子, shown in the list too.
    @State private var extraDay: Date?
    /// The day heading something is being dragged over.
    @State private var dropTarget: Date?
    @State private var pickingDate = false
    /// Days whose list is open on the left (only today at first; the rest start folded).
    @State private var openDays: Set<Date> = [Calendar.current.startOfDay(for: Date())]

    private let cal = Calendar.current
    private var board: Board { store.board }
    private var today: Date { cal.startOfDay(for: Date()) }
    private static let accent = Color(hex: "#2A78D6")

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            planColumn
                .frame(maxWidth: .infinity)
            if !pickHidden {
                resizeHandle
                pickColumn
                    .frame(width: pickWidth * fontScale)
                    .transition(.move(edge: .trailing))
            }
        }
    }

    /// The divider between the plan and the pick panel: drag it to change the panel's width.
    private var resizeHandle: some View {
        ZStack {
            Color.clear
            Divider()
        }
        .frame(width: 8)
        .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { v in
                    let start = dragStartWidth ?? pickWidth
                    if dragStartWidth == nil { dragStartWidth = start }
                    pickWidth = min(700, max(200, start - v.translation.width / fontScale))
                }
                .onEnded { _ in dragStartWidth = nil })
            .help(L("拖动调整右边的宽度"))
    }

    // MARK: The plan

    /// The days shown on the left, top to bottom: earlier days that still have a plan (two
    /// weeks back), today and the next six days, then any later day that has a plan.
    private var planDays: [Date] {
        let planned = Set(board.tasks.flatMap { t in [t.planDay] + t.subtasks.map(\.planDay) }.compactMap { $0 }
            .map { cal.startOfDay(for: $0) })
        let start = cal.date(byAdding: .day, value: -14, to: today)!
        let week = (0..<7).map { cal.date(byAdding: .day, value: $0, to: today)! }
        let past = planned.filter { $0 >= start && $0 < today && !board.plan(for: $0).isEmpty }
        let later = planned.filter { $0 > week.last! }
        return Set(past).union(week).union(later).union(extraDay.map { [$0] } ?? []).sorted()
    }

    private var planColumn: some View {
        let days = planDays
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("计划")).scaledFont(.title2, weight: .bold)
                Text(L("点日期展开或收起；把右边的任务或子任务拖到某一天上，就排进那天")).scaledFont(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { pickingDate = true } label: { Label(L("其他日子"), systemImage: "calendar") }
                    .buttonStyle(.borderless)
                    .help(L("排更远的某一天"))
                    .popover(isPresented: $pickingDate) {
                        DatePicker("", selection: Binding(get: { extraDay ?? today }, set: {
                        let d = cal.startOfDay(for: $0)
                        extraDay = d
                        openDays.insert(d)
                        pickingDate = false
                    }), displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .padding(10)
                    }
                if pickHidden {
                    Button { withAnimation(.snappy) { pickHidden = false } } label: {
                        Label(L("加任务"), systemImage: "sidebar.right")
                    }
                    .help(L("打开右边的日程"))
                }
            }
            ScrollViewReader { proxy in
                List {
                    ForEach(days, id: \.self) { d in
                        let plan = board.plan(for: d)
                        Section {
                            if openDays.contains(d) {
                            if plan.isEmpty {
                                Text(d < today ? L("没有安排") : L("还没有安排，从右边加任务进来"))
                                    .scaledFont(.callout)
                                    .foregroundStyle(.tertiary)
                                    .padding(.vertical, 4)
                                    .listRowSeparator(.hidden)
                            }
                            ForEach(Array(plan.enumerated()), id: \.element.id) { i, item in
                                PlanRow(item: item, day: d, number: i + 1, count: plan.count, onEdit: onEdit,
                                        move: { offset in move(plan, from: i, to: i + offset) })
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                            }
                            .onMove { from, to in
                                var refs = plan.map(\.ref)
                                refs.move(fromOffsets: from, toOffset: to)
                                withAnimation(.snappy) { store.reorderPlan(refs) }
                            }
                            }
                        } header: {
                            dayHeader(d, plan)
                        }
                        .id(d)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear { proxy.scrollTo(today, anchor: .top) }
            }
        }
        .padding(20)
    }

    /// A day's heading: its name and date, how much is done, and (for earlier days) moving
    /// what's left to today. Click it to make it the day ＋ adds to.
    private func dayHeader(_ d: Date, _ plan: [PlanItem]) -> some View {
        let done = plan.filter { board.isDone($0) }.count
        let leftOver = plan.filter { !board.isDone($0) && !board.isDone($0.task) }
        let isToday = cal.isDate(d, inSameDayAs: today)
        let open = openDays.contains(d)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Click: open or fold the day.
            Button {
                withAnimation(.snappy) {
                    if open { openDays.remove(d) } else { openDays.insert(d) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "chevron.right")
                        .scaledFont(.caption, weight: .bold)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(isToday ? L("今天") : d.formatted(.dateTime.weekday()))
                        .scaledFont(isToday ? .title2 : .title3, weight: .bold)
                        .foregroundStyle(d < today ? Color.secondary : Color.primary)
                    Text(isToday ? d.formatted(.dateTime.month().day().weekday()) : d.formatted(.dateTime.month().day()))
                        .scaledFont(.callout)
                        .foregroundStyle(.secondary)
                    if !plan.isEmpty {
                        Text(L("完成 \(done) / \(plan.count)"))
                            .scaledFont(.caption, monospacedDigit: true)
                            .foregroundStyle(done == plan.count ? Color.green : Color.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? L("收起这一天") : L("展开这一天"))
            Spacer()
            if d < today, !leftOver.isEmpty {
                Button(L("没做完的 \(leftOver.count) 个移到今天")) {
                    withAnimation(.snappy) { store.addToPlan(leftOver.map(\.ref), day: today) }
                }
                .buttonStyle(.link)
                .scaledFont(.caption)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
        .padding(.horizontal, 6)
        .background(dropTarget == d ? Self.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(dropTarget == d ? Self.accent : Color.clear, lineWidth: 1.5))
        .textCase(nil)
        // Drop tasks or subtasks dragged from the agenda (or a plan) onto a day to plan them there.
        .dropDestination(for: String.self) { items, _ in
            let refs = items.compactMap(PlanDrag.ref)
            guard !refs.isEmpty else { return false }
            withAnimation(.snappy) {
                store.addToPlan(refs, day: d)
                openDays.insert(d)
            }
            return true
        } isTargeted: { over in
            if over { dropTarget = d } else if dropTarget == d { dropTarget = nil }
        }
    }

    /// Right-click menu for a ＋: put it on another day instead.
    @ViewBuilder
    private func addMenu(_ refs: [PlanItem.Ref]) -> some View {
        ForEach(Date.planChoices, id: \.self) { d in
            Button(L("加到\(d.planDayName)")) { withAnimation(.snappy) { store.addToPlan(refs, day: d) } }
        }
    }

    /// "已排在明天" when it's on another day's plan (today or later).
    private func plannedElsewhere(_ planDay: Date?) -> String? {
        guard let d = planDay, d >= today, !cal.isDate(d, inSameDayAs: today) else { return nil }
        return L("已排在\(d.planDayName)")
    }

    private func move(_ plan: [PlanItem], from: Int, to: Int) {
        guard plan.indices.contains(to) else { return }
        var refs = plan.map(\.ref)
        refs.swapAt(from, to)
        withAnimation(.snappy) { store.reorderPlan(refs) }
    }

    // MARK: Picking

    private struct Pick: Identifiable {
        let id: String
        let title: String
        var isOverdue = false
        let items: [(PlanItem, String)]
    }

    /// The agenda (日程): open tasks — and dated subtasks — by date: overdue, today, each of
    /// the next days, later, then those without a date. What's already on today's plan is
    /// left out (a planned task still shows while it has subtasks left to pick).
    private var picks: [Pick] {
        let q = search.trimmingCharacters(in: .whitespaces)
        func matches(_ t: PlannerTask, _ sub: Subtask? = nil) -> Bool {
            q.isEmpty || t.title.localizedCaseInsensitiveContains(q)
                || (sub?.title.localizedCaseInsensitiveContains(q) ?? t.subtasks.contains { $0.title.localizedCaseInsensitiveContains(q) })
                || board.tags(for: t).contains { $0.name.localizedCaseInsensitiveContains(q) }
        }
        var dated: [(item: PlanItem, date: Date, detail: String)] = []
        var undated: [(PlanItem, String)] = []
        for t in board.tasks where !board.isDone(t) {
            if !t.isPlanned(on: today) || !openSubtasks(t).isEmpty, matches(t) {
                if let date = board.agendaDate(t), let d = t.sortedDates.first(where: { $0.date == date }) {
                    dated.append((PlanItem(task: t), date, "\(d.kind.title) \(d.label)"))
                } else {
                    undated.append((PlanItem(task: t), board.column(t.columnID)?.name ?? ""))
                }
            }
            for sub in t.subtasks where !sub.isDone && !sub.isPlanned(on: today) && matches(t, sub) {
                guard let date = sub.date, sub.isOverdue || date >= today else { continue }
                dated.append((PlanItem(task: t, subtask: sub), date, L("「\(t.title)」的子任务 · \(sub.dateLabel ?? "")")))
            }
        }
        dated.sort { $0.date < $1.date }
        var sections: [Pick] = []
        let overdue = dated.filter { $0.date < today }
        if !overdue.isEmpty { sections.append(Pick(id: "overdue", title: L("已过期"), isOverdue: true, items: overdue.map { ($0.item, $0.detail) })) }
        for offset in 0...agendaDays {
            let start = cal.date(byAdding: .day, value: offset, to: today)!
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let items = dated.filter { $0.date >= start && $0.date < end }
            guard !items.isEmpty else { continue }
            let name = offset == 0 ? L("今天") : ""
            let label = start.formatted(.dateTime.month().day().weekday())
            sections.append(Pick(id: "day-\(offset)", title: name.isEmpty ? label : "\(name) · \(label)", items: items.map { ($0.item, $0.detail) }))
        }
        let limit = cal.date(byAdding: .day, value: agendaDays + 1, to: today)!
        let later = dated.filter { $0.date >= limit }
        if !later.isEmpty { sections.append(Pick(id: "later", title: L("以后"), items: later.map { ($0.item, $0.detail) })) }
        if !undated.isEmpty { sections.append(Pick(id: "undated", title: L("没有日期"), items: undated)) }
        return sections
    }

    private var pickColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("日程")).scaledFont(.headline)
                Text(L("点 ＋ 加到今天，或拖到左边某一天")).scaledFont(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { withAnimation(.snappy) { pickHidden = true } } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(.borderless)
                    .help(L("收起这一栏"))
            }
            TextField(L("新任务，回车添加到\(today.planDayName)"), text: $newTask)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addNewTask)
                .help(L("新建一个任务并放进这天的计划。可以顺便写 #标签、明天、周五、!高 等，和快速添加一样"))
            HStack {
                TextField(L("搜索任务"), text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker(L("范围"), selection: $agendaDays) {
                    Text(L("7 天")).tag(7)
                    Text(L("14 天")).tag(14)
                    Text(L("30 天")).tag(30)
                }
                .labelsHidden()
                .fixedSize()
                .help(L("按日期列出多少天"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let groups = picks
                    if groups.isEmpty {
                        Text(search.isEmpty ? L("没完成的任务都已经排进\(today.planDayName)的计划了。") : L("没有找到。"))
                            .scaledFont(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(g.title) · \(g.items.count)")
                                    .scaledFont(.caption, weight: .semibold)
                                    .foregroundStyle(g.isOverdue ? .red : .secondary)
                                Spacer()
                                if g.id != "undated", g.id != "later", g.items.count > 1 {
                                    Button(L("全部加入")) { withAnimation(.snappy) { store.addToPlan(g.items.map(\.0.ref), day: today) } }
                                        .buttonStyle(.link)
                                        .scaledFont(.caption)
                                }
                            }
                            ForEach(g.items, id: \.0.id) { item, detail in
                                if let sub = item.subtask {
                                    subPickRow(item.task, sub, detail, overdue: g.isOverdue)
                                } else {
                                    pickRow(item.task, detail)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.025))
    }

    private func addNewTask() {
        let text = newTask.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let id = store.quickAdd(QuickParse(text, board: board)) else { return }
        withAnimation(.snappy) { store.addToPlan([id], day: today) }
        newTask = ""
    }

    /// A dated subtask in the agenda.
    private func subPickRow(_ task: PlannerTask, _ sub: Subtask, _ detail: String, overdue: Bool) -> some View {
        HStack(spacing: 8) {
            let ref = PlanItem.Ref(taskID: task.id, subtaskID: sub.id)
            Button { withAnimation(.snappy) { store.addToPlan([ref], day: today) } } label: {
                Image(systemName: "plus.circle").foregroundStyle(Self.accent)
            }
            .buttonStyle(.borderless)
            .help(L("加到\(today.planDayName)的计划（右键可选别的日子）"))
            .contextMenu { addMenu([ref]) }
            Image(systemName: "arrow.turn.down.right").scaledFont(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Button(sub.title.isEmpty ? L("（无标题）") : sub.title) { onEdit(task) }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                Text([detail, plannedElsewhere(sub.planDay)].compactMap { $0 }.joined(separator: " · "))
                    .scaledFont(.caption).foregroundStyle(overdue ? .red : .secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .scaledFont(.callout)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .draggable(PlanDrag.string(PlanItem.Ref(taskID: task.id, subtaskID: sub.id))) { dragPreview(sub.title) }
    }

    private func dragPreview(_ title: String) -> some View {
        Text(title)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Self.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Subtasks not done and not yet on the chosen day's plan.
    private func openSubtasks(_ task: PlannerTask) -> [Subtask] {
        task.subtasks.filter { !$0.isDone && !$0.isPlanned(on: today) }
    }

    @ViewBuilder
    private func pickRow(_ task: PlannerTask, _ detail: String) -> some View {
        let subs = openSubtasks(task)
        let open = expanded.contains(task.id)
        HStack(spacing: 8) {
            if task.isPlanned(on: today) {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    .help(L("这个任务已经在\(today.planDayName)的计划里，还可以单独加它的子任务"))
            } else {
                Button { withAnimation(.snappy) { store.addToPlan([task.id], day: today) } } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Self.accent)
                }
                .buttonStyle(.borderless)
                .help(L("加到\(today.planDayName)的计划（右键可选别的日子）"))
                .contextMenu { addMenu([PlanItem.Ref(taskID: task.id)]) }
            }
            Circle()
                .fill(board.tags(for: task).first.map { Color(hex: $0.colorHex) } ?? Color.gray.opacity(0.4))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Button(task.title.isEmpty ? L("（无标题）") : task.title) { onEdit(task) }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                let info = [detail.isEmpty ? nil : detail, plannedElsewhere(task.planDay)].compactMap { $0 }.joined(separator: " · ")
                if !info.isEmpty {
                    Text(info).scaledFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !subs.isEmpty {
                Button { withAnimation(.snappy) { if open { expanded.remove(task.id) } else { expanded.insert(task.id) } } } label: {
                    HStack(spacing: 3) {
                        Text(L("子任务 \(subs.count)"))
                        Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("把子任务单独加进计划"))
            }
        }
        .scaledFont(.callout)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .draggable(PlanDrag.string(PlanItem.Ref(taskID: task.id))) { dragPreview(task.title) }
        if open {
            ForEach(subs) { sub in
                HStack(spacing: 8) {
                    let ref = PlanItem.Ref(taskID: task.id, subtaskID: sub.id)
                    Button { withAnimation(.snappy) { store.addToPlan([ref], day: today) } } label: {
                        Image(systemName: "plus.circle").foregroundStyle(Self.accent)
                    }
                    .buttonStyle(.borderless)
                    .help(L("加到\(today.planDayName)的计划（右键可选别的日子）"))
                    .contextMenu { addMenu([ref]) }
                    Text(sub.title.isEmpty ? L("（无标题）") : sub.title).lineLimit(1)
                    Spacer(minLength: 0)
                    if let label = sub.dateLabel {
                        Text(label).scaledFont(.caption).foregroundStyle(sub.isOverdue ? .red : .secondary)
                    }
                }
                .scaledFont(.callout)
                .padding(.leading, 26)
                .padding(.vertical, 1)
                .contentShape(Rectangle())
                .draggable(PlanDrag.string(PlanItem.Ref(taskID: task.id, subtaskID: sub.id))) { dragPreview(sub.title) }
            }
        }
    }
}

/// One item on a day's plan (a task, or a subtask with its task named under it): its
/// number, a box to tick, what it is, and buttons.
private struct PlanRow: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.fontScale) private var fontScale
    let item: PlanItem
    let day: Date
    let number: Int
    let count: Int
    let onEdit: (PlannerTask) -> Void
    let move: (Int) -> Void
    @State private var hovering = false
    /// Folded subtask list (shown by default so they're visible without opening the task).
    @State private var subtasksFolded = false

    private var board: Board { store.board }

    var body: some View {
        let task = item.task
        let done = board.isDone(item)
        let tag = board.tags(for: task).first
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13 * fontScale, weight: .bold, design: .rounded))
                .foregroundStyle(done ? Color.secondary : Color.white)
                .frame(width: 24 * fontScale, height: 24 * fontScale)
                .background(Circle().fill(done ? Color.primary.opacity(0.08) : Color(hex: "#2A78D6")))
            Button {
                withAnimation(.snappy) {
                    if let sub = item.subtask { store.toggleSubtask(task.id, sub.id) } else { store.toggleDone(task.id) }
                }
            } label: {
                // Subtasks tick in a square, tasks in a circle.
                Image(systemName: item.subtask == nil ? (done ? "checkmark.circle.fill" : "circle")
                                                      : (done ? "checkmark.square.fill" : "square"))
                    .font(.system(size: 18 * fontScale))
                    .foregroundStyle(done ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(done ? L("标为没完成") : L("完成"))
            VStack(alignment: .leading, spacing: 3) {
                Button { onEdit(task) } label: {
                    Text(item.title.isEmpty ? L("（无标题）") : item.title)
                        .scaledFont(.body, weight: .medium)
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    if let tag { TagChip(tag: tag, small: true) }
                    if let sub = item.subtask {
                        Label(L("「\(task.title)」的子任务"), systemImage: "arrow.turn.down.right")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let label = sub.dateLabel {
                            Label(label, systemImage: "calendar").foregroundStyle(sub.isOverdue ? Color.red : Color.secondary)
                        }
                    } else {
                    if let column = board.column(task.columnID) {
                        Text(column.name).foregroundStyle(.secondary)
                    }
                    if let d = task.dates.filter({ $0.kind == .deadline }).min(by: { $0.date < $1.date }) {
                        Label(d.label, systemImage: "flag")
                            .foregroundStyle(board.isOverdue(d, of: task) ? Color.red : Color.secondary)
                    }
                    if !task.subtasks.isEmpty {
                        Button { withAnimation(.snappy) { subtasksFolded.toggle() } } label: {
                            HStack(spacing: 3) {
                                Label(L("子任务 \(task.subtaskProgress.done)/\(task.subtaskProgress.total)"), systemImage: "checklist")
                                Image(systemName: "chevron.right").rotationEffect(.degrees(subtasksFolded ? 0 : 90))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(subtasksFolded ? L("展开子任务") : L("收起子任务"))
                    }
                    let waits = board.waitingOn(task)
                    if !waits.isEmpty {
                        Label(board.describe(waits), systemImage: "link").foregroundStyle(.purple).lineLimit(1)
                    }
                    }
                }
                .scaledFont(.caption)
                if item.subtask == nil, !task.subtasks.isEmpty, !subtasksFolded {
                    subtaskList(task)
                }
            }
            Spacer(minLength: 8)
            if !done {
                FocusMenu(task: task, compact: true)
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
            }
            HStack(spacing: 2) {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(number == 1)
                    .help(L("往前"))
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(number == count)
                    .help(L("往后"))
                Menu {
                    ForEach(Date.planChoices.filter { !Calendar.current.isDate($0, inSameDayAs: day) }, id: \.self) { d in
                        Button(L("改到\(d.planDayName)")) { withAnimation(.snappy) { store.addToPlan([item.ref], day: d) } }
                    }
                } label: {
                    Image(systemName: "calendar.badge.clock")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("改到别的日子"))
                Button { withAnimation(.snappy) { store.removeFromPlan(item.ref) } } label: { Image(systemName: "xmark") }
                    .help(L("从这天的计划里拿掉（任务本身不会删除）"))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0.35)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            if let tag { UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10).fill(Color(hex: tag.colorHex)).frame(width: 4) }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
        .opacity(done ? 0.7 : 1)
        .onHover { hovering = $0 }
    }

    /// The task's subtasks, tickable right here.
    private func subtaskList(_ task: PlannerTask) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(task.subtasks) { sub in
                Button { withAnimation(.snappy) { store.toggleSubtask(task.id, sub.id) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: sub.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(sub.isDone ? Color.green : Color.secondary)
                        Text(sub.title.isEmpty ? L("（无标题）") : sub.title)
                            .strikethrough(sub.isDone, color: .secondary)
                            .foregroundStyle(sub.isDone ? .secondary : .primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let label = sub.dateLabel {
                            Text(label).scaledFont(.caption).foregroundStyle(sub.isOverdue ? Color.red : Color.secondary)
                        }
                        if let d = sub.planDay, d >= Calendar.current.startOfDay(for: Date()), !sub.isDone {
                            Label(d.planDayName, systemImage: "calendar").scaledFont(.caption).foregroundStyle(.orange)
                                .help(L("这个子任务单独排在\(d.planDayName)"))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .scaledFont(.callout)
                .draggable(PlanDrag.string(PlanItem.Ref(taskID: task.id, subtaskID: sub.id))) {
                    Text(sub.title).padding(6).background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.top, 4)
    }
}

/// What's carried when a task or subtask is dragged onto a day: "plan|taskID|subtaskID".
enum PlanDrag {
    static func string(_ ref: PlanItem.Ref) -> String { "plan|\(ref.taskID)|\(ref.subtaskID ?? "")" }

    static func ref(_ s: String) -> PlanItem.Ref? {
        let parts = s.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "plan", !parts[1].isEmpty else { return nil }
        return PlanItem.Ref(taskID: String(parts[1]), subtaskID: parts[2].isEmpty ? nil : String(parts[2]))
    }
}
