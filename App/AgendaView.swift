import SwiftUI

/// 日程: open tasks from every status, by date — overdue, today, tomorrow, the next days, later.
struct AgendaView: View {
    @EnvironmentObject private var store: BoardStore
    /// Tasks allowed by the current search / tag filter.
    let visibleIDs: Set<String>
    let onEdit: (PlannerTask) -> Void
    @AppStorage("agendaDays") private var days = 7

    var body: some View {
        let sections = store.board.agendaSections(days: days)
            .map { AgendaSection(id: $0.id, title: $0.title, tasks: $0.tasks.filter { visibleIDs.contains($0.id) }, isOverdue: $0.isOverdue) }
            .filter { !$0.tasks.isEmpty || $0.id == "day-0" }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(L("日程")).scaledFont(.title2, weight: .bold)
                    Text(L("所有状态里没完成、有日期的任务")).scaledFont(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker(L("范围"), selection: $days) {
                        Text(L("7 天")).tag(7)
                        Text(L("14 天")).tag(14)
                        Text(L("30 天")).tag(30)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(section.title)
                                .scaledFont(.headline)
                                .foregroundStyle(section.isOverdue ? Color.red : .primary)
                            Text("\(section.tasks.count)")
                                .scaledFont(.caption, monospacedDigit: true)
                                .foregroundStyle(.secondary)
                        }
                        if section.tasks.isEmpty {
                            Text(L("今天没有到期的任务 🎉"))
                                .scaledFont(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        }
                        ForEach(section.tasks) { task in
                            AgendaRow(task: task, onEdit: { onEdit(task) })
                        }
                    }
                }
                if sections.allSatisfy({ $0.tasks.isEmpty }) {
                    Text(L("给任务加上截止、开始、里程碑或提醒日期，就会出现在这里。"))
                        .scaledFont(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct AgendaRow: View {
    @EnvironmentObject private var store: BoardStore
    let task: PlannerTask
    let onEdit: () -> Void
    @State private var hovering = false

    var body: some View {
        let board = store.board
        let column = board.column(task.columnID)
        let date = board.agendaDate(task)
        let dateInfo = task.sortedDates.first { $0.date == date }
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { store.toggleDone(task.id) }
            } label: {
                Image(systemName: "circle")
                    .scaledFont(.title3)
                    .foregroundStyle(board.accentColor(of: task))
            }
            .buttonStyle(.plain)
            .help(board.columns.contains(where: \.isDone) ? L("完成（移到完成列）") : L("还没有设置「完成列」"))
            .disabled(!board.columns.contains(where: \.isDone))

            PriorityMark(level: board.priority(of: task))
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).scaledFont(.body, weight: .medium).lineLimit(2)
                HStack(spacing: 6) {
                    if let column {
                        Text(column.icon.isEmpty ? column.name : "\(column.icon) \(column.name)")
                            .scaledFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(board.tags(for: task).prefix(3)) { TagChip(tag: $0, small: true) }
                    let p = task.subtaskProgress
                    if p.total > 0 {
                        Label("\(p.done)/\(p.total)", systemImage: "checklist")
                            .scaledFont(.caption, monospacedDigit: true)
                            .foregroundStyle(.secondary)
                    }
                    if task.recurrence != .none {
                        Image(systemName: "repeat").scaledFont(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let d = dateInfo {
                let overdue = board.isOverdue(d, of: task)
                Label(d.showsTime ? d.date.formatted(.dateTime.month().day().hour().minute())
                                          : d.date.formatted(.dateTime.month().day()),
                      systemImage: d.kind.symbol)
                    .scaledFont(.caption)
                    .foregroundStyle(overdue ? .red : d.kind.color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(task.backgroundHex.map(Color.init(hex:)) ?? Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(hovering ? 0.12 : 0.05), radius: hovering ? 4 : 1.5, y: 1)
        )
        .foregroundStyle(task.backgroundHex.map { Color(hex: $0).contrastingText } ?? Color.primary)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button(L("编辑…"), action: onEdit)
            Menu(L("移到")) {
                ForEach(store.columns) { c in
                    Button(c.name) { store.move(task.id, to: c.id) }.disabled(c.id == task.columnID)
                }
            }
        }
    }
}
