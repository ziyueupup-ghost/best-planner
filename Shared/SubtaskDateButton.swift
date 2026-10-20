import SwiftUI

/// A subtask's due day: a calendar icon when there's none, otherwise the date (red when
/// overdue). Tapping opens a calendar to pick or clear it.
struct SubtaskDateButton: View {
    @Binding var date: Date?
    @Binding var hasTime: Bool
    var isDone = false
    @State private var picking = false

    private var overdue: Bool {
        guard let date, !isDone else { return false }
        return hasTime ? date < Date() : date < Calendar.current.startOfDay(for: Date())
    }

    /// Keeps the chosen time of day when the day changes (or none without a time).
    private func set(_ day: Date) {
        let cal = Calendar.current
        guard hasTime, let old = date else { date = cal.startOfDay(for: day); return }
        let t = cal.dateComponents([.hour, .minute], from: old)
        date = cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: day)
    }

    var body: some View {
        Button {
            picking = true
        } label: {
            if let date {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                    Text(hasTime ? date.shortTimeLabel : date.shortLabel).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(overdue ? Color.red : Color.secondary)
            } else {
                Image(systemName: "calendar.badge.plus").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .help(L("子任务日期"))
        .popover(isPresented: $picking) {
            VStack(spacing: 10) {
                DatePicker(L("日期"), selection: Binding(get: { date ?? Date() }, set: { set($0) }),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    Toggle(L("具体时间"), isOn: Binding(get: { hasTime }, set: { on in
                        hasTime = on
                        if on, let d = date, Calendar.current.startOfDay(for: d) == d {
                            date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d)
                        }
                        if !on, let d = date { date = Calendar.current.startOfDay(for: d) }
                    }))
                    if hasTime {
                        DatePicker("", selection: Binding(get: { date ?? Date() }, set: { date = $0 }),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    if date != nil {
                        Button(L("清除日期"), role: .destructive) { date = nil; picking = false }
                    }
                    Spacer()
                    Button(L("完成")) {
                        if date == nil { date = Calendar.current.startOfDay(for: Date()) }
                        picking = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
            .frame(width: 300)
            #if os(iOS)
            .presentationCompactAdaptation(.popover)
            #endif
        }
    }
}
