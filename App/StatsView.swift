import Charts
import SwiftUI

/// 统计: completions and focus time over recent days, completions by tag, top focus tasks.
struct StatsView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fontScale) private var fontScale

    private struct DayValue: Identifiable {
        let day: Date
        let value: Int
        var id: Date { day }
    }

    private struct TagValue: Identifiable {
        let tag: Tag
        let value: Int
        var id: String { tag.id }
    }

    var body: some View {
        let board = store.board
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<14).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today

        let completed = board.tasks.filter { board.isDone($0) && $0.completedAt != nil }
        let completedPerDay = days.map { d in
            DayValue(day: d, value: completed.filter { cal.isDate($0.completedAt!, inSameDayAs: d) }.count)
        }
        let sessions = board.tasks.flatMap(\.focusSessions)
        let focusPerDay = days.map { d in
            DayValue(day: d, value: sessions.filter { cal.isDate($0.start, inSameDayAs: d) }.reduce(0) { $0 + $1.minutes })
        }
        let monthAgo = cal.date(byAdding: .day, value: -30, to: today)!
        let byTag = board.tags.map { tag in
            TagValue(tag: tag, value: completed.filter { $0.completedAt! >= monthAgo && $0.tagIDs.contains(tag.id) }.count)
        }.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let topFocus = board.tasks.filter { $0.focusMinutes > 0 }.sorted { $0.focusMinutes > $1.focusMinutes }.prefix(5)

        let weekDone = completed.filter { $0.completedAt! >= weekStart }.count
        let weekFocus = sessions.filter { $0.start >= weekStart }.reduce(0) { $0 + $1.minutes }
        let weekCreated = board.tasks.filter { $0.createdAt >= weekStart }.count
        let open = board.tasks.filter { !board.isDone($0) }.count

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("统计", systemImage: "chart.bar.xaxis").scaledFont(.title2, weight: .bold)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        tile("本周完成", "\(weekDone)", "个任务", .green)
                        tile("本周专注", weekFocus >= 60 ? String(format: "%.1f", Double(weekFocus) / 60) : "\(weekFocus)",
                             weekFocus >= 60 ? "小时" : "分钟", .orange)
                        tile("本周新建", "\(weekCreated)", "个任务", .blue)
                        tile("还没完成", "\(open)", "个任务", .purple)
                    }

                    section("最近 14 天完成的任务") {
                        Chart(completedPerDay) { d in
                            BarMark(x: .value("日期", d.day, unit: .day), y: .value("完成", d.value))
                                .foregroundStyle(Color.green.gradient)
                        }
                        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.defaultDigits).day()) } }
                        .frame(height: 150 * fontScale)
                    }

                    section("最近 14 天专注时间（分钟）") {
                        if sessions.isEmpty {
                            Text("还没有专注记录。在任务的右键菜单或编辑窗口里点「开始专注 🍅」。")
                                .scaledFont(.callout).foregroundStyle(.secondary)
                        } else {
                            Chart(focusPerDay) { d in
                                BarMark(x: .value("日期", d.day, unit: .day), y: .value("分钟", d.value))
                                    .foregroundStyle(Color.orange.gradient)
                            }
                            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.defaultDigits).day()) } }
                            .frame(height: 150 * fontScale)
                        }
                    }

                    section("最近 30 天按标签完成") {
                        if byTag.isEmpty {
                            Text("最近 30 天还没有带标签的已完成任务。").scaledFont(.callout).foregroundStyle(.secondary)
                        } else {
                            Chart(byTag) { t in
                                BarMark(x: .value("完成", t.value), y: .value("标签", t.tag.name))
                                    .foregroundStyle(t.tag.color)
                                    .annotation(position: .trailing) { Text("\(t.value)").scaledFont(.caption) }
                            }
                            .frame(height: CGFloat(max(byTag.count, 1)) * 28 * fontScale + 20)
                        }
                    }

                    if !topFocus.isEmpty {
                        section("专注时间最多的任务") {
                            ForEach(Array(topFocus)) { t in
                                HStack {
                                    Text(t.title).lineLimit(1)
                                    Spacer()
                                    Text("🍅 \(t.focusMinutes) 分钟").scaledFont(.callout, monospacedDigit: true).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(20)
        .frame(width: FontScale.sheetSize(width: 640, height: 680, scale: fontScale).width,
               height: FontScale.sheetSize(width: 640, height: 680, scale: fontScale).height)
        .onExitCommand { dismiss() }
    }

    private func tile(_ title: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).scaledFont(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).scaledFont(.title, weight: .bold).foregroundStyle(color)
                Text(unit).scaledFont(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).scaledFont(.headline)
            content()
        }
    }
}
