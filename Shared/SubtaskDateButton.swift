import SwiftUI

/// A subtask's due day: a calendar icon when there's none, otherwise the date (red when
/// overdue). Tapping opens a calendar to pick or clear it.
struct SubtaskDateButton: View {
    @Binding var date: Date?
    var isDone = false
    @State private var picking = false

    private var overdue: Bool {
        guard let date, !isDone else { return false }
        return date < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        Button {
            picking = true
        } label: {
            if let date {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                    Text(date.shortLabel).monospacedDigit()
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
                DatePicker(L("日期"), selection: Binding(get: { date ?? Date() }, set: { date = Calendar.current.startOfDay(for: $0) }),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
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
