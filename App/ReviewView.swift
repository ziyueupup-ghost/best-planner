import SwiftUI

/// 回顾: a month calendar of what got done, a day's detail with its 今日总结, and 成就.
struct ReviewView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.fontScale) private var fontScale
    let onEdit: (PlannerTask) -> Void
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var selected = Calendar.current.startOfDay(for: Date())
    @State private var showAchievements = false

    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2   // weeks start on Monday
        return c
    }

    var body: some View {
        let review = store.board.review()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(review)
                monthSummary(review)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        calendarGrid(review).frame(width: 380 * fontScale)
                        DayDetail(day: selected, activity: review.activity(on: selected), onEdit: onEdit)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        calendarGrid(review)
                        DayDetail(day: selected, activity: review.activity(on: selected), onEdit: onEdit)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showAchievements) {
            AchievementsView(review: review)
                .appFontSize()
        }
    }

    // MARK: Header: streak and achievements

    private func header(_ r: ReviewData) -> some View {
        let unlocked = r.achievements.filter(\.isUnlocked).count
        return HStack(spacing: 12) {
            Text(L("回顾")).scaledFont(.title2, weight: .bold)
            Spacer()
            badge("🔥", L("连续 \(r.currentStreak) 天"), L("最长 \(r.longestStreak) 天"))
            badge("✅", L("共完成 \(r.totalCompleted)"), L("个任务"))
            Button {
                showAchievements = true
            } label: {
                badge("🏆", L("成就 \(unlocked)/\(r.achievements.count)"), L("点击查看"))
            }
            .buttonStyle(.plain)
        }
    }

    private func badge(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 6) {
            Text(icon).scaledFont(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).scaledFont(.callout, weight: .semibold)
                Text(sub).scaledFont(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Month summary

    private func monthSummary(_ r: ReviewData) -> some View {
        let range = cal.dateInterval(of: .month, for: month)!
        let inMonth = r.days.filter { range.contains($0.key) }
        let done = inMonth.values.reduce(0) { $0 + $1.completed.count }
        let subs = inMonth.values.reduce(0) { $0 + $1.subtasks.count }
        let focus = inMonth.values.reduce(0) { $0 + $1.focusMinutes }
        let activeDays = inMonth.values.filter(\.didSomething).count
        let best = inMonth.max { $0.value.completed.count + $0.value.subtasks.count < $1.value.completed.count + $1.value.subtasks.count }
        return HStack(spacing: 10) {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Text(month.formatted(.dateTime.year().month(.wide)))
                .scaledFont(.headline)
                .frame(minWidth: 110 * fontScale)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            Button(L("本月")) {
                month = cal.dateInterval(of: .month, for: Date())!.start
                selected = cal.startOfDay(for: Date())
            }
            Spacer()
            Text(L("完成 \(done) 个任务 · \(subs) 个子任务 · 专注 \(focus / 60) 小时 \(focus % 60) 分 · 有产出 \(activeDays) 天")
                 + (best.map { $0.value.didSomething ? L(" · 最高产：\($0.key.formatted(.dateTime.month().day()))") : "" } ?? ""))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }

    private func shiftMonth(_ n: Int) {
        month = cal.date(byAdding: .month, value: n, to: month)!
    }

    // MARK: Calendar

    private func calendarGrid(_ r: ReviewData) -> some View {
        let start = cal.dateInterval(of: .month, for: month)!.start
        let count = cal.range(of: .day, in: .month, for: month)!.count
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: start)! }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach([L("一"), L("二"), L("三"), L("四"), L("五"), L("六"), L("日")], id: \.self) { d in
                    Text(d).scaledFont(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date, r.activity(on: date))
                    } else {
                        Color.clear.frame(height: 46 * fontScale)
                    }
                }
            }
            HStack(spacing: 4) {
                Spacer()
                Text(L("少")).scaledFont(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5) { l in RoundedRectangle(cornerRadius: 3).fill(heat(l)).frame(width: 12, height: 12) }
                Text(L("多")).scaledFont(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func dayCell(_ date: Date, _ a: DayActivity) -> some View {
        let isSelected = cal.isDate(date, inSameDayAs: selected)
        let isToday = cal.isDateInToday(date)
        let future = date > Date()
        let hasNote = store.board.dayNotes[Board.dayKey(date)] != nil
        return Button {
            selected = cal.startOfDay(for: date)
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: date))")
                    .scaledFont(.callout, weight: isToday ? .bold : .regular)
                    .foregroundStyle(a.level >= 3 ? Color.white : (future ? Color.secondary : Color.primary))
                HStack(spacing: 2) {
                    if !a.completed.isEmpty {
                        Text("✓\(a.completed.count)").scaledFont(.caption2, monospacedDigit: true)
                    }
                    if hasNote { Text("📝").scaledFont(.caption2) }
                }
                .foregroundStyle(a.level >= 3 ? Color.white.opacity(0.9) : Color.secondary)
                .frame(height: 12 * fontScale)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46 * fontScale)
            .background(heat(a.level), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : (isToday ? Color.accentColor.opacity(0.5) : .clear),
                                  lineWidth: isSelected ? 2.5 : 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(a.isEmpty ? L("这天没有记录") : L("完成 \(a.completed.count) 个任务、\(a.subtasks.count) 个子任务"))
    }

    private func heat(_ level: Int) -> Color {
        level == 0 ? Color.primary.opacity(0.05) : Color.green.opacity([0, 0.25, 0.45, 0.7, 0.92][level])
    }
}

/// One day: summary, what was finished, subtasks, notes, and the 今日总结.
private struct DayDetail: View {
    @EnvironmentObject private var store: BoardStore
    let day: Date
    let activity: DayActivity
    let onEdit: (PlannerTask) -> Void
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(day.formatted(.dateTime.year().month().day().weekday(.wide)))
                .scaledFont(.title3, weight: .semibold)
            HStack(spacing: 8) {
                stat(L("完成任务"), activity.completed.count, .green)
                stat(L("完成子任务"), activity.subtasks.count, .blue)
                stat(L("专注分钟"), activity.focusMinutes, .orange)
                stat(L("新建任务|stat"), activity.created.count, .purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L("今日总结")).scaledFont(.headline)
                TextEditor(text: $note)
                    .scaledFont(.body)
                    .frame(minHeight: 70)
                    .padding(6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        if note.isEmpty {
                            Text(L("这一天做了什么、有什么收获…（自动保存）"))
                                .scaledFont(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                    }
            }

            if !activity.completed.isEmpty {
                section(L("✅ 完成了")) {
                    ForEach(Array(activity.completed.enumerated()), id: \.offset) { _, c in
                        taskLine(c.task, time: c.at)
                    }
                }
            }
            if !activity.subtasks.isEmpty {
                section(L("☑️ 勾掉的子任务")) {
                    ForEach(Array(groupedSubtasks.enumerated()), id: \.offset) { _, g in
                        VStack(alignment: .leading, spacing: 2) {
                            Button(g.task.title) { openTask(g.task) }
                                .buttonStyle(.plain)
                                .scaledFont(.callout, weight: .medium)
                            Text(g.titles.joined(separator: "、"))
                                .scaledFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !activity.notes.isEmpty {
                section(L("💬 写下的记录")) {
                    ForEach(Array(activity.notes.enumerated()), id: \.offset) { _, n in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(n.text).scaledFont(.callout)
                            Text("\(n.task.title) · \(n.at.formatted(.dateTime.hour().minute()))")
                                .scaledFont(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !activity.created.isEmpty {
                section(L("➕ 新建的任务")) {
                    ForEach(activity.created) { t in taskLine(t, time: nil) }
                }
            }
            if activity.isEmpty {
                Text(day > Date() ? L("还没到这一天。") : L("这一天没有完成记录。"))
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { note = store.board.dayNotes[Board.dayKey(day)] ?? "" }
        .onChange(of: day) { _, d in note = store.board.dayNotes[Board.dayKey(d)] ?? "" }
        .onChange(of: note) { _, text in store.setDayNote(text, for: day) }
    }

    private var groupedSubtasks: [(task: PlannerTask, titles: [String])] {
        var order: [String] = []
        var map: [String: (PlannerTask, [String])] = [:]
        for s in activity.subtasks {
            if map[s.task.id] == nil { order.append(s.task.id); map[s.task.id] = (s.task, []) }
            map[s.task.id]!.1.append(s.title)
        }
        return order.map { (map[$0]!.0, map[$0]!.1) }
    }

    private func stat(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").scaledFont(.title2, weight: .bold).foregroundStyle(color)
            Text(title).scaledFont(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).scaledFont(.headline)
            content()
        }
    }

    private func taskLine(_ task: PlannerTask, time: Date?) -> some View {
        let board = store.board
        let deleted = !board.tasks.contains { $0.id == task.id }
        return HStack(spacing: 6) {
            PriorityMark(level: board.priority(of: task))
            Button(task.title) { openTask(task) }
                .buttonStyle(.plain)
                .scaledFont(.callout)
                .disabled(deleted)
            ForEach(board.tags(for: task).prefix(2)) { TagChip(tag: $0, small: true) }
            if deleted { Text(L("已删除")).scaledFont(.caption2).foregroundStyle(.tertiary) }
            Spacer()
            if let time { Text(time.formatted(.dateTime.hour().minute())).scaledFont(.caption, monospacedDigit: true).foregroundStyle(.secondary) }
        }
    }

    private func openTask(_ task: PlannerTask) {
        if let current = store.task(task.id) { onEdit(current) }
    }
}

/// All achievements: unlocked ones with their date, locked ones with progress.
struct AchievementsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fontScale) private var fontScale
    let review: ReviewData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("🏆 成就")).scaledFont(.title2, weight: .bold)
                Text(L("已解锁 \(review.achievements.filter(\.isUnlocked).count)/\(review.achievements.count)"))
                    .scaledFont(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(L("完成")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170 * fontScale), spacing: 10)], spacing: 10) {
                    ForEach(review.achievements.sorted { ($0.isUnlocked ? 0 : 1) < ($1.isUnlocked ? 0 : 1) }) { a in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(a.icon).font(.system(size: 30 * fontScale))
                                    .grayscale(a.isUnlocked ? 0 : 1)
                                    .opacity(a.isUnlocked ? 1 : 0.4)
                                Spacer()
                                if a.isUnlocked { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                            }
                            Text(a.title).scaledFont(.headline)
                            Text(a.detail).scaledFont(.caption).foregroundStyle(.secondary)
                            if let at = a.unlockedAt {
                                Text(L("\(at.dayLabel) 解锁")).scaledFont(.caption2).foregroundStyle(.green)
                            } else {
                                ProgressView(value: Double(a.progress), total: Double(a.target))
                                Text("\(a.progress) / \(a.target)").scaledFont(.caption2, monospacedDigit: true).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((a.isUnlocked ? Color.yellow : Color.primary).opacity(a.isUnlocked ? 0.12 : 0.04),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(20)
        .frame(width: FontScale.sheetSize(width: 620, height: 600, scale: fontScale).width,
               height: FontScale.sheetSize(width: 620, height: 600, scale: fontScale).height)
        .onExitCommand { dismiss() }
    }
}
