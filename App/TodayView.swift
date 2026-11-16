import SwiftUI

/// 今日: the tasks and subtasks picked for today, in the order to do them. Drag (or ↑↓) to
/// reorder, tick to finish, × to take one off the plan. On the right: what to pick from —
/// overdue first, then due or starting today, then in progress, then the rest; a task's
/// subtasks can be picked one by one. What's left over from an earlier day's plan can be
/// moved to today in one go.
struct TodayView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.fontScale) private var fontScale
    let onEdit: (PlannerTask) -> Void

    @State private var search = ""
    @State private var showLeftOver = false
    /// Tasks whose subtasks are shown in the pick list.
    @State private var expanded: Set<String> = []
    /// The pick panel on the right: its width (drag the divider) and whether it's folded away.
    @AppStorage("todayPickWidth") private var pickWidth = 320.0
    @AppStorage("todayPickHidden") private var pickHidden = false
    @State private var dragStartWidth: Double?

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

    private var planColumn: some View {
        let plan = board.plan(for: today)
        let done = plan.filter { board.isDone($0) }.count
        let leftOver = board.leftOver(before: today)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("今天")).scaledFont(.title2, weight: .bold)
                Text(Date().formatted(.dateTime.month().day().weekday(.wide)))
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if !plan.isEmpty {
                    Text(L("完成 \(done) / \(plan.count)"))
                        .scaledFont(.callout, weight: .medium, monospacedDigit: true)
                }
                if pickHidden {
                    Button { withAnimation(.snappy) { pickHidden = false } } label: {
                        Label(L("加任务"), systemImage: "sidebar.right")
                    }
                    .help(L("打开右边的「加到今天」"))
                }
            }
            if !plan.isEmpty {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule().fill(Self.accent)
                            .frame(width: geo.size.width * Double(done) / Double(plan.count))
                    }
                }
                .frame(height: 6)
                .animation(.snappy, value: done)
            }
            if !leftOver.isEmpty { leftOverBanner(leftOver) }
            if plan.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sun.max").font(.system(size: 34 * fontScale)).foregroundStyle(.orange)
                    Text(L("今天还没有安排。")).scaledFont(.headline)
                    Text(L("从右边挑几个任务加进来，再拖动排好先后顺序。"))
                        .scaledFont(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                Spacer()
            } else {
                List {
                    ForEach(Array(plan.enumerated()), id: \.element.id) { i, item in
                        PlanRow(item: item, number: i + 1, count: plan.count, onEdit: onEdit,
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
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                Text(L("拖动任务可以调整顺序；做完了直接打勾。"))
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private func move(_ plan: [PlanItem], from: Int, to: Int) {
        guard plan.indices.contains(to) else { return }
        var refs = plan.map(\.ref)
        refs.swapAt(from, to)
        withAnimation(.snappy) { store.reorderPlan(refs) }
    }

    private func leftOverBanner(_ tasks: [PlanItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.uturn.forward.circle").foregroundStyle(.orange)
                Text(L("之前的计划还有 \(tasks.count) 个没完成")).scaledFont(.callout, weight: .medium)
                Spacer()
                Button(showLeftOver ? L("收起") : L("看看")) { withAnimation(.snappy) { showLeftOver.toggle() } }
                    .buttonStyle(.link)
                Button(L("全部移到今天")) { withAnimation(.snappy) { store.addToPlan(tasks.map(\.ref)) } }
            }
            if showLeftOver {
                ForEach(tasks) { t in
                    HStack(spacing: 8) {
                        Text(t.planDay?.shortLabel ?? "").scaledFont(.caption, monospacedDigit: true).foregroundStyle(.secondary)
                        Button(t.subtask == nil ? t.title : "\(t.title) · \(t.task.title)") { onEdit(t.task) }
                            .buttonStyle(.plain)
                            .lineLimit(1)
                        Spacer()
                        Button { withAnimation(.snappy) { store.addToPlan([t.ref]) } } label: { Image(systemName: "plus.circle") }
                            .buttonStyle(.borderless)
                            .help(L("移到今天"))
                        Button { store.removeFromPlan(t.ref) } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help(L("不做了，从计划里拿掉"))
                    }
                    .scaledFont(.callout)
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Picking

    private struct Pick: Identifiable {
        let id: String
        let title: String
        let tasks: [(PlannerTask, String)]
    }

    private var picks: [Pick] {
        let q = search.trimmingCharacters(in: .whitespaces)
        // Open tasks that are off today's plan themselves, or still have subtasks to pick.
        var left = board.tasks.filter { t in
            !board.isDone(t) && (!t.isPlanned(on: today) || !openSubtasks(t).isEmpty)
                && (q.isEmpty || t.title.localizedCaseInsensitiveContains(q)
                    || t.subtasks.contains { $0.title.localizedCaseInsensitiveContains(q) }
                    || board.tags(for: t).contains { $0.name.localizedCaseInsensitiveContains(q) })
        }
        func take(_ match: (PlannerTask) -> String?) -> [(PlannerTask, String)] {
            let found = left.compactMap { t in match(t).map { (t, $0) } }
            left.removeAll { t in found.contains { $0.0.id == t.id } }
            return found
        }
        let overdue = take { t in t.dates.first { board.isOverdue($0, of: t) }.map { L("截止 \($0.label)") } }
        let dueToday = take { t in t.dates.first { cal.isDateInToday($0.date) }.map { "\($0.kind.title) \($0.label)" } }
        let doing = take { t in board.isStarted(t) ? board.column(t.columnID)?.name ?? "" : nil }
        let soon = take { t in
            t.dates.filter { $0.dueDate > today && $0.dueDate < cal.date(byAdding: .day, value: 7, to: today)! }
                .min { $0.date < $1.date }.map { "\($0.kind.title) \($0.label)" }
        }
        let rest = take { t in board.column(t.columnID)?.name ?? "" }
        return [Pick(id: "overdue", title: L("已逾期"), tasks: overdue),
                Pick(id: "today", title: L("今天到期或开始"), tasks: dueToday),
                Pick(id: "doing", title: L("进行中"), tasks: doing),
                Pick(id: "soon", title: L("这周要到期"), tasks: soon),
                Pick(id: "rest", title: L("其他待办"), tasks: rest)].filter { !$0.tasks.isEmpty }
    }

    private var pickColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("加到今天")).scaledFont(.headline)
                Spacer()
                Button { withAnimation(.snappy) { pickHidden = true } } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(.borderless)
                    .help(L("收起这一栏"))
            }
            TextField(L("搜索任务"), text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let groups = picks
                    if groups.isEmpty {
                        Text(search.isEmpty ? L("没完成的任务都已经在今天的计划里了。") : L("没有找到。"))
                            .scaledFont(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(g.title) · \(g.tasks.count)")
                                    .scaledFont(.caption, weight: .semibold)
                                    .foregroundStyle(g.id == "overdue" ? .red : .secondary)
                                Spacer()
                                if g.id != "rest", g.tasks.count > 1 {
                                    Button(L("全部加入")) { withAnimation(.snappy) { store.addToPlan(g.tasks.map(\.0.id)) } }
                                        .buttonStyle(.link)
                                        .scaledFont(.caption)
                                }
                            }
                            ForEach(g.tasks, id: \.0.id) { t, detail in
                                pickRow(t, detail)
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

    /// Subtasks not done and not yet on today's plan.
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
                    .help(L("这个任务已经在今天的计划里，还可以单独加它的子任务"))
            } else {
                Button { withAnimation(.snappy) { store.addToPlan([task.id]) } } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Self.accent)
                }
                .buttonStyle(.borderless)
                .help(L("加到今天的计划"))
            }
            Circle()
                .fill(board.tags(for: task).first.map { Color(hex: $0.colorHex) } ?? Color.gray.opacity(0.4))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Button(task.title.isEmpty ? L("（无标题）") : task.title) { onEdit(task) }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).scaledFont(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                .help(L("把子任务单独加到今天"))
            }
        }
        .scaledFont(.callout)
        .padding(.vertical, 3)
        if open {
            ForEach(subs) { sub in
                HStack(spacing: 8) {
                    Button { withAnimation(.snappy) { store.addToPlan([PlanItem.Ref(taskID: task.id, subtaskID: sub.id)]) } } label: {
                        Image(systemName: "plus.circle").foregroundStyle(Self.accent)
                    }
                    .buttonStyle(.borderless)
                    .help(L("把这个子任务加到今天的计划"))
                    Text(sub.title.isEmpty ? L("（无标题）") : sub.title).lineLimit(1)
                    Spacer(minLength: 0)
                    if let label = sub.dateLabel {
                        Text(label).scaledFont(.caption).foregroundStyle(sub.isOverdue ? .red : .secondary)
                    }
                }
                .scaledFont(.callout)
                .padding(.leading, 26)
                .padding(.vertical, 1)
            }
        }
    }
}

/// One item on today's plan (a task, or a subtask with its task named under it): its
/// number, a box to tick, what it is, and buttons.
private struct PlanRow: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.fontScale) private var fontScale
    let item: PlanItem
    let number: Int
    let count: Int
    let onEdit: (PlannerTask) -> Void
    let move: (Int) -> Void
    @State private var hovering = false

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
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
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
                        Label("\(task.subtaskProgress.done)/\(task.subtaskProgress.total)", systemImage: "checklist")
                            .foregroundStyle(.secondary)
                    }
                    let waits = board.waitingOn(task)
                    if !waits.isEmpty {
                        Label(board.describe(waits), systemImage: "link").foregroundStyle(.purple).lineLimit(1)
                    }
                    }
                }
                .scaledFont(.caption)
            }
            Spacer(minLength: 8)
            if hovering && !done {
                FocusMenu(task: task)
                    .fixedSize()
            }
            HStack(spacing: 2) {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(number == 1)
                    .help(L("往前"))
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(number == count)
                    .help(L("往后"))
                Button { withAnimation(.snappy) { store.removeFromPlan(item.ref) } } label: { Image(systemName: "xmark") }
                    .help(L("从今天的计划里拿掉（任务本身不会删除）"))
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
}
