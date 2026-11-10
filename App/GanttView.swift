import SwiftUI

/// 甘特图, kept simple: a small table on the left (开始 / 截止, click to pick a day; 前置 =
/// the row numbers this task waits for, like "1, 3") and plain bars on the right (drag to
/// move, drag the ends to change the dates). Arrows show who waits for whom (前后顺序,
/// Shared/Dependencies.swift); here a task always waits for the other to finish.
struct GanttView: View {
    @EnvironmentObject private var store: BoardStore
    @EnvironmentObject private var selection: TaskSelection
    @Environment(\.fontScale) private var fontScale
    /// The task whose card is showing (after a click on its bar).
    @State private var preview: String?
    /// Tasks passing the board's search / tag filter.
    let visibleIDs: Set<String>
    let onEdit: (PlannerTask) -> Void

    @AppStorage("ganttDayWidth") private var dayWidth = 30.0
    @AppStorage("ganttShowDone") private var showDone = false
    /// The table on the left is folded away (names then go after the bars).
    @AppStorage("ganttListHidden") private var listHidden = false
    /// Tag groups folded shut (tag ids, "none" for untagged), comma-separated.
    @AppStorage("ganttCollapsedTags") private var collapsedTags = ""

    private func isCollapsed(_ key: String) -> Bool { collapsedTags.split(separator: ",").contains(Substring(key)) }
    private func toggleCollapsed(_ key: String) {
        var keys = collapsedTags.split(separator: ",").map(String.init)
        if let i = keys.firstIndex(of: key) { keys.remove(at: i) } else { keys.append(key) }
        collapsedTags = keys.joined(separator: ",")
    }

    private enum DragPart { case move, start, end }
    @State private var dragging: (id: String, part: DragPart, days: Int)?

    private let cal = Calendar.current
    private var rowHeight: CGFloat { 30 * fontScale }
    private var headerHeight: CGFloat { 40 * fontScale }
    private var day: CGFloat { CGFloat(dayWidth) * fontScale }
    private var board: Board { store.board }

    /// Every shown task: by start date (then due date), tasks without dates last in board order.
    private var rows: [PlannerTask] {
        let columnIndex = Dictionary(uniqueKeysWithValues: board.columns.enumerated().map { ($0.element.id, $0.offset) })
        func key(_ t: PlannerTask) -> (Date, Date, Int, Double) {
            let span = t.ganttSpan
            return (span?.start ?? .distantFuture, span?.end ?? .distantFuture, columnIndex[t.columnID] ?? 99, t.order)
        }
        return board.tasks
            .filter { visibleIDs.contains($0.id) && (showDone || !board.isDone($0)) }
            .sorted { key($0) < key($1) }
    }

    /// A row of the chart: a tag's heading, or a task.
    fileprivate struct Line: Identifiable {
        let id: String
        var task: PlannerTask?
        var tag: Tag?
        var count = 0
        var groupKey = ""
    }

    /// The tasks grouped by tag (a task with several tags goes under the first, in the
    /// order of the tag list), untagged ones last. No headings when nothing is tagged.
    private func lines(_ rows: [PlannerTask]) -> [Line] {
        let tagOrder = board.tags.map(\.id)
        func group(_ t: PlannerTask) -> String? { tagOrder.first { t.tagIDs.contains($0) } }
        let groups = Dictionary(grouping: rows, by: group)
        if groups.keys.allSatisfy({ $0 == nil }) { return rows.map { Line(id: $0.id, task: $0) } }
        var out: [Line] = []
        for key in tagOrder.map(Optional.some) + [nil] {
            guard let tasks = groups[key], !tasks.isEmpty else { continue }
            let groupKey = key ?? "none"
            out.append(Line(id: "tag-\(groupKey)", tag: key.flatMap { k in board.tags.first { $0.id == k } },
                            count: tasks.count, groupKey: groupKey))
            if !isCollapsed(groupKey) { out += tasks.map { Line(id: $0.id, task: $0) } }
        }
        return out
    }

    /// First day on the chart and how many days it shows.
    private func range(_ rows: [PlannerTask]) -> (first: Date, days: Int) {
        let today = cal.startOfDay(for: Date())
        let spans = rows.compactMap(\.ganttSpan)
        let marks = rows.flatMap { $0.dates.filter { $0.kind == .milestone }.map { cal.startOfDay(for: $0.date) } }
        let first = cal.date(byAdding: .day, value: -3, to: (spans.map(\.start) + marks + [today]).min()!)!
        let last = cal.date(byAdding: .day, value: 10, to: (spans.map(\.end) + marks + [today]).max()!)!
        return (first, max(35, dayCount(from: first, to: last) + 1))
    }

    private func dayCount(from a: Date, to b: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
    }

    var body: some View {
        let rows = rows
        let lines = lines(rows)
        // Exactly the window's width: the timeline scrolls sideways inside it.
        GeometryReader { geo in
            VStack(spacing: 0) {
                controls
                Divider()
                if rows.isEmpty {
                    Text(L("这里还没有任务。")).foregroundStyle(.secondary).padding(30)
                    Spacer()
                } else {
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            if !listHidden {
                                table(lines)
                                Divider()
                            }
                            chart(lines, rows)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button { withAnimation(.snappy) { listHidden.toggle() } } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.borderless)
            .help(listHidden ? L("展开左边的列表") : L("收起左边的列表"))
            Text(L("拖动横条改日期。「等第几行」填行号（比如 1 或 1, 3）：那几行完成后，这一行才能开始。"))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            Toggle(L("显示已完成"), isOn: $showDone)
                .toggleStyle(.checkbox)
            HStack(spacing: 4) {
                Button { dayWidth = max(14, dayWidth - 6) } label: { Image(systemName: "minus.magnifyingglass") }
                    .help(L("缩小"))
                Button { dayWidth = min(80, dayWidth + 6) } label: { Image(systemName: "plus.magnifyingglass") }
                    .help(L("放大"))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Table

    struct Widths {
        let number, title, date, preds: CGFloat
        init(_ s: CGFloat) { number = 30 * s; title = 180 * s; date = 64 * s; preds = 64 * s }
        var total: CGFloat { number + title + date * 2 + preds + 12 }
    }

    private func table(_ lines: [Line]) -> some View {
        let w = Widths(fontScale)
        let tasks = lines.compactMap(\.task)
        let numbers = Dictionary(uniqueKeysWithValues: tasks.enumerated().map { ($0.element.id, $0.offset + 1) })
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("#").frame(width: w.number)
                Text(L("任务")).frame(width: w.title, alignment: .leading)
                Text(L("开始")).frame(width: w.date, alignment: .leading)
                Text(L("截止")).frame(width: w.date, alignment: .leading)
                Text(L("等第几行")).frame(width: w.preds, alignment: .leading)
            }
            .scaledFont(.caption, weight: .semibold)
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
            .frame(height: headerHeight, alignment: .bottom)
            .padding(.bottom, 4)
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                if let task = line.task {
                    GanttTableRow(task: task, number: numbers[task.id] ?? 0, numbers: numbers, widths: w,
                                  height: rowHeight, onEdit: onEdit, preview: $preview)
                        .background(i % 2 == 1 ? Color.primary.opacity(0.025) : .clear)
                } else {
                    tagHeading(line)
                }
            }
        }
        .frame(width: w.total)
    }

    /// A tag group's heading: click it to fold the group.
    private func tagHeading(_ line: Line) -> some View {
        Button { withAnimation(.snappy) { toggleCollapsed(line.groupKey) } } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed(line.groupKey) ? 0 : 90))
                if let tag = line.tag { TagChip(tag: tag, small: true) } else { Text(L("无标签")).foregroundStyle(.secondary) }
                Text("\(line.count)")
                    .scaledFont(.caption, monospacedDigit: true)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 10)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.06))
        .help(isCollapsed(line.groupKey) ? L("展开这一组") : L("收起这一组"))
    }

    // MARK: Chart

    private func chart(_ lines: [Line], _ rows: [PlannerTask]) -> some View {
        let range = range(rows)
        let width = CGFloat(range.days) * day
        let height = CGFloat(lines.count) * rowHeight
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    header(range)
                    ZStack(alignment: .topLeading) {
                        grid(lines, range, height: height)
                        arrows(lines, range)
                        ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                            if let task = line.task {
                                if let span = task.ganttSpan {
                                    bar(task, start: span.start, end: span.end, index: i, range: range)
                                }
                                milestones(task, index: i, range: range)
                            } else if listHidden {
                                // Without the table, the group headings sit on the chart.
                                tagHeading(line)
                                    .fixedSize()
                                    .offset(y: CGFloat(i) * rowHeight)
                            }
                        }
                        // Scroll target: a little before today.
                        Color.clear.frame(width: 1, height: 1)
                            .padding(.leading, max(0, x(cal.date(byAdding: .day, value: -2, to: Date())!, range)))
                            .id("today")
                    }
                    .frame(width: width, height: height, alignment: .topLeading)
                }
            }
            .onAppear { proxy.scrollTo("today", anchor: .leading) }
        }
    }

    private func x(_ date: Date, _ range: (first: Date, days: Int)) -> CGFloat {
        CGFloat(dayCount(from: range.first, to: date)) * day
    }

    private func header(_ range: (first: Date, days: Int)) -> some View {
        Canvas { ctx, size in
            for i in 0..<range.days {
                guard let d = cal.date(byAdding: .day, value: i, to: range.first) else { continue }
                let left = CGFloat(i) * day
                let n = cal.component(.day, from: d)
                if n == 1 || i == 0 {
                    ctx.draw(Text(d.formatted(.dateTime.year().month(.abbreviated))).font(.caption.weight(.semibold)),
                             at: CGPoint(x: left + 4, y: 12), anchor: .leading)
                }
                let today = cal.isDateInToday(d)
                if day >= 18 || n % 2 == 1 || today {
                    ctx.draw(Text("\(n)").font(.caption2.monospacedDigit().weight(today ? .bold : .regular))
                        .foregroundColor(today ? .accentColor : cal.isDateInWeekend(d) ? .secondary : .primary),
                             at: CGPoint(x: left + day / 2, y: size.height - 12))
                }
            }
        }
        .frame(width: CGFloat(range.days) * day, height: headerHeight + 4)
    }

    private func grid(_ lines: [Line], _ range: (first: Date, days: Int), height: CGFloat) -> some View {
        Canvas { ctx, size in
            for (i, line) in lines.enumerated() where line.task == nil || i % 2 == 1 {
                ctx.fill(Path(CGRect(x: 0, y: CGFloat(i) * rowHeight, width: size.width, height: rowHeight)),
                         with: .color(.primary.opacity(line.task == nil ? 0.06 : 0.025)))
            }
            for i in 0..<range.days {
                guard let d = cal.date(byAdding: .day, value: i, to: range.first), cal.isDateInWeekend(d) else { continue }
                ctx.fill(Path(CGRect(x: CGFloat(i) * day, y: 0, width: day, height: size.height)), with: .color(.primary.opacity(0.035)))
            }
            let today = x(Date(), range) + day / 2
            ctx.stroke(Path { $0.move(to: CGPoint(x: today, y: 0)); $0.addLine(to: CGPoint(x: today, y: size.height)) },
                       with: .color(.accentColor.opacity(0.6)), lineWidth: 1)
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }

    // MARK: Bars

    private func liveSpan(_ id: String, _ start: Date, _ end: Date) -> (Date, Date) {
        guard let d = dragging, d.id == id else { return (start, end) }
        var s = start, e = end
        if d.part != .end { s = cal.date(byAdding: .day, value: d.days, to: s)! }
        if d.part != .start { e = cal.date(byAdding: .day, value: d.days, to: e)! }
        return (min(s, e), max(s, e))
    }

    private func barRect(_ id: String, _ start: Date, _ end: Date, _ index: Int, _ range: (first: Date, days: Int)) -> CGRect {
        let (s, e) = liveSpan(id, start, end)
        let left = x(s, range)
        return CGRect(x: left + 2, y: CGFloat(index) * rowHeight + 7,
                      width: x(e, range) + day - left - 4, height: rowHeight - 14)
    }

    private static let barColor = Color(hex: "#5B85F5")

    private func bar(_ task: PlannerTask, start: Date, end: Date, index: Int, range: (first: Date, days: Int)) -> some View {
        let rect = barRect(task.id, start, end, index, range)
        let done = board.isDone(task)
        let progress = task.subtasks.isEmpty ? (done ? 1.0 : 0.0)
            : Double(task.subtaskProgress.done) / Double(task.subtaskProgress.total)
        // The colour of its (first) tag, like the group it's in; untagged ones blue.
        let tagHex = board.tags.first { task.tagIDs.contains($0.id) }?.colorHex
        let color = done ? Color.gray : tagHex.map(Color.init(hex:)) ?? Self.barColor
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.35))
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: max(0, rect.width * progress))
        }
        .frame(width: rect.width, height: rect.height)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) { edgeHandle(task, .start, start: start, end: end) }
        .overlay(alignment: .trailing) { edgeHandle(task, .end, start: start, end: end) }
        .gesture(dragGesture(task, .move, start: start, end: end))
        .onTapGesture { preview = task.id }
        .contextMenu { barMenu(task) }
        .help(spanHelp(task, start, end))
        .popover(isPresented: Binding(get: { preview == task.id }, set: { if !$0 { preview = nil } }), arrowEdge: .bottom) {
            cardPreview(task)
        }
        .position(x: rect.midX, y: rect.midY)
        .overlay(alignment: .topLeading) {
            // With the table folded away, the name goes after the bar.
            if listHidden {
                Text(task.title)
                    .scaledFont(.caption)
                    .foregroundStyle(board.isDone(task) ? .secondary : .primary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: rect.height)
                    .offset(x: rect.maxX + 6, y: rect.minY)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 里程碑 dates of the task as small diamonds in its row.
    private func milestones(_ task: PlannerTask, index: Int, range: (first: Date, days: Int)) -> some View {
        ForEach(task.dates.filter { $0.kind == .milestone }) { d in
            Image(systemName: "diamond.fill")
                .font(.system(size: 11 * fontScale))
                .foregroundStyle(.orange)
                .help(d.note.isEmpty ? L("里程碑 \(d.date.shortLabel)") : L("里程碑 \(d.date.shortLabel)：\(d.note)"))
                .position(x: x(d.date, range) + day / 2, y: CGFloat(index) * rowHeight + rowHeight / 2)
        }
    }

    /// The task's card, as on the board (click it to open the editor).
    private func cardPreview(_ task: PlannerTask) -> some View {
        GanttCardPreview(taskID: task.id, onEdit: { t in preview = nil; onEdit(t) })
            .environmentObject(store)
            .environmentObject(selection)
            .appFontSize()
    }

    private func spanHelp(_ task: PlannerTask, _ start: Date, _ end: Date) -> String {
        let span = cal.isDate(start, inSameDayAs: end) ? start.shortLabel : "\(start.shortLabel) – \(end.shortLabel)"
        let waits = board.waitingOn(task)
        return waits.isEmpty ? "\(task.title)\n\(span)" : "\(task.title)\n\(span)\n\(board.describe(waits))"
    }

    private func edgeHandle(_ task: PlannerTask, _ part: DragPart, start: Date, end: Date) -> some View {
        Color.clear
            .frame(width: 7)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(dragGesture(task, part, start: start, end: end))
    }

    private func dragGesture(_ task: PlannerTask, _ part: DragPart, start: Date, end: Date) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { v in dragging = (task.id, part, Int((v.translation.width / day).rounded())) }
            .onEnded { _ in
                guard let d = dragging, d.id == task.id else { return }
                let (s, e) = liveSpan(task.id, start, end)
                dragging = nil
                if d.days != 0 { store.setGanttSpan(task.id, start: s, end: e) }
            }
    }

    @ViewBuilder
    private func barMenu(_ task: PlannerTask) -> some View {
        Button(L("打开这个任务")) { onEdit(task) }
        if !task.dependencies.isEmpty {
            Divider()
            ForEach(task.dependencies) { d in
                let name = board.tasks.first { $0.id == d.taskID }?.title ?? L("已删除的任务")
                Button(L("不等「\(name)」了")) { store.removeDependency(task.id, d.id) }
            }
        }
    }

    // MARK: Arrows

    /// A thin line from the end (or start) of the task waited for, down to the row of the
    /// waiting task, then across to its start (or end).
    private func arrows(_ lines: [Line], _ range: (first: Date, days: Int)) -> some View {
        let index = Dictionary(uniqueKeysWithValues: lines.enumerated().compactMap { i, l in l.task.map { ($0.id, i) } })
        return Canvas { ctx, _ in
            let color = Color.secondary.opacity(0.7)
            for (i, line) in lines.enumerated() {
                guard let task = line.task, let span = task.ganttSpan else { continue }
                let to = barRect(task.id, span.start, span.end, i, range)
                for d in task.dependencies {
                    guard let j = index[d.taskID], let otherTask = lines[j].task, let other = otherTask.ganttSpan else { continue }
                    let from = barRect(otherTask.id, other.start, other.end, j, range)
                    let sx = d.kind.needsOtherFinished ? from.maxX : from.minX
                    let tx = d.kind.gatesStart ? to.minX : to.maxX
                    let elbowX = d.kind.needsOtherFinished ? sx + 5 : sx - 5
                    var path = Path()
                    path.move(to: CGPoint(x: sx, y: from.midY))
                    path.addLine(to: CGPoint(x: elbowX, y: from.midY))
                    path.addLine(to: CGPoint(x: elbowX, y: to.midY))
                    path.addLine(to: CGPoint(x: tx, y: to.midY))
                    ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                    let dir: CGFloat = tx >= elbowX ? 1 : -1
                    var head = Path()
                    head.move(to: CGPoint(x: tx, y: to.midY))
                    head.addLine(to: CGPoint(x: tx - 5 * dir, y: to.midY - 3))
                    head.addLine(to: CGPoint(x: tx - 5 * dir, y: to.midY + 3))
                    head.closeSubpath()
                    ctx.fill(head, with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// One row of the Gantt table: number, name, start, due, days, predecessors.
private struct GanttTableRow: View {
    @EnvironmentObject private var store: BoardStore
    let task: PlannerTask
    let number: Int
    let numbers: [String: Int]
    let widths: GanttView.Widths
    let height: CGFloat
    let onEdit: (PlannerTask) -> Void
    @Binding var preview: String?
    @EnvironmentObject private var selection: TaskSelection

    @State private var predsText = ""
    @State private var picking: Bool?   // true: the start, false: the due date
    @State private var predsError = false

    private let cal = Calendar.current
    private var board: Board { store.board }
    private var span: (start: Date, end: Date)? { task.ganttSpan }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(number)")
                .scaledFont(.caption, monospacedDigit: true)
                .foregroundStyle(.secondary)
                .frame(width: widths.number)
            Button { preview = task.id } label: {
                HStack(spacing: 5) {
                    Circle().fill(board.column(task.columnID)?.color ?? .gray).frame(width: 6, height: 6)
                    Text(task.title.isEmpty ? L("（无标题）") : task.title)
                        .strikethrough(board.isDone(task), color: .secondary)
                        .foregroundStyle(board.isDone(task) ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("看这个任务的卡片"))
            .popover(isPresented: Binding(get: { preview == task.id }, set: { if !$0 { preview = nil } }), arrowEdge: .trailing) {
                GanttCardPreview(taskID: task.id, onEdit: { t in preview = nil; onEdit(t) })
                    .environmentObject(store)
                    .environmentObject(selection)
                    .appFontSize()
            }
            .frame(width: widths.title)
            dateCell(span?.start, isStart: true)
                .frame(width: widths.date, alignment: .leading)
            dateCell(span?.end, isStart: false)
                .frame(width: widths.date, alignment: .leading)
            TextField("", text: $predsText, prompt: Text("—"))
                .textFieldStyle(.plain)
                .foregroundStyle(predsError ? Color.red : Color.primary)
                .padding(.leading, 6)
                .frame(width: widths.preds, alignment: .leading)
                .onSubmit(applyPreds)
                .help(predsHelp)
        }
        .scaledFont(.callout)
        .frame(height: height)
        .onAppear(perform: refresh)
        .onChange(of: task) { _, _ in refresh() }
        .onChange(of: numbers) { _, _ in refresh() }
    }

    private func dayCount(_ a: Date, _ b: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
    }

    /// A short date ("8/11"); click it to pick another day on a calendar ("+" when empty).
    private func dateCell(_ date: Date?, isStart: Bool) -> some View {
        Button { picking = isStart } label: {
            Text(date?.shortLabel ?? "+")
                .monospacedDigit()
                .foregroundStyle(date == nil ? .secondary : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(picking == isStart ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isStart ? L("开始日期") : L("截止日期"))
        .popover(isPresented: Binding(get: { picking == isStart }, set: { if !$0 { picking = nil } })) {
            DatePicker("", selection: Binding(get: { date ?? cal.startOfDay(for: Date()) }, set: { setDay($0, isStart: isStart) }),
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(10)
        }
    }

    /// A new start moves the whole task (it keeps its length); a new due date stretches it.
    private func setDay(_ picked: Date, isStart: Bool) {
        let day = cal.startOfDay(for: picked)
        if isStart {
            let length = span.map { dayCount($0.start, $0.end) } ?? 0
            store.setGanttSpan(task.id, start: day, end: cal.date(byAdding: .day, value: length, to: day)!)
        } else {
            store.setGanttSpan(task.id, start: span.map { min($0.start, day) } ?? day, end: day)
        }
    }

    private var predsHelp: String {
        let names = task.dependencies.compactMap { d in board.tasks.first { $0.id == d.taskID }.map { "「\($0.title)」" } }
        let hint = L("填要等的任务的行号，用逗号隔开，按回车。等那些任务完成，这个才能开始。")
        return names.isEmpty ? hint : L("在等：\(names.joined(separator: "、"))") + "\n" + hint
    }

    private func refresh() {
        predsText = task.dependencies.compactMap { numbers[$0.taskID].map(String.init) }.joined(separator: ", ")
        predsError = false
    }

    /// "1, 3" → wait for rows 1 and 3 to finish. Links to tasks not shown in the table are kept.
    private func applyPreds() {
        let byNumber = Dictionary(uniqueKeysWithValues: numbers.map { ($0.value, $0.key) })
        var result = task.dependencies.filter { numbers[$0.taskID] == nil }
        for token in predsText.split(whereSeparator: { !$0.isNumber }) {
            guard let n = Int(token), let otherID = byNumber[n], otherID != task.id,
                  !board.wouldLoop(task.id, waitingFor: otherID) else { predsError = true; return }
            guard !result.contains(where: { $0.taskID == otherID }) else { continue }
            // Keep a link that's already there as it is.
            result.append(task.dependencies.first { $0.taskID == otherID } ?? TaskDependency(taskID: otherID))
        }
        store.setDependencies(task.id, result)
        predsError = false
    }
}

/// A task's board card in a popover, kept up to date with the store.
private struct GanttCardPreview: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.fontScale) private var fontScale
    let taskID: String
    let onEdit: (PlannerTask) -> Void

    var body: some View {
        if let task = store.task(taskID) {
            TaskCard(task: task, onEdit: { onEdit(task) })
                .frame(width: 290 * fontScale)
                .padding(10)
        }
    }
}
