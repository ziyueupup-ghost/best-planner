import SwiftUI

/// Edits a custom repetition: every N days / weeks / months / years, and for weeks the
/// weekdays (Monday first). Used by the task editors on the Mac and the iPhone.
struct RepeatRuleEditor: View {
    @Binding var rule: RepeatRule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L("每|repeat-every"))
                Stepper(value: $rule.interval, in: 1...99) {
                    Text("\(rule.interval)").monospacedDigit().frame(minWidth: 22)
                }
                .fixedSize()
                Picker("", selection: $rule.unit) {
                    ForEach(RepeatRule.Unit.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            if rule.unit == .week {
                HStack(spacing: 5) {
                    ForEach(RepeatRule.weekdayOrder, id: \.self) { day in
                        let on = rule.weekdays.contains(day)
                        Button {
                            if on { rule.weekdays.removeAll { $0 == day } } else { rule.weekdays.append(day) }
                        } label: {
                            Text(RepeatRule.weekdayName(day))
                                .font(.callout.weight(on ? .semibold : .regular))
                                .frame(width: 30, height: 30)
                                .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                                .foregroundStyle(on ? Color.white : Color.primary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Text(L("规则：\(rule.title)。完成后按这个规则生成下一次，日期也往后推。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension RepeatRule {
    /// A sensible start when "custom" is first chosen: weekly, on this weekday.
    static func starting(on date: Date = Date()) -> RepeatRule {
        RepeatRule(unit: .week, interval: 1, weekdays: [Calendar.current.component(.weekday, from: date)])
    }
}
