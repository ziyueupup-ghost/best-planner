import Foundation

/// Parses a quick-add line like "交初稿 明天下午3点 #论文修改 !紧急 @进行中".
///   #标签  → tag (created if it doesn't exist)
///   !名称  → priority (by name, emoji, or position: !1 is the most important)
///   @名称  → status column (name prefix)
///   dates  → 今天/明天/后天/大后天, 周五/星期五/下周三, 10月15日, 10/15, 2026-10-15
///   times  → 下午3点, 3点半, 15:30, 晚上8点20
/// A date with a time becomes a 提醒 (notifies at that time); without a time it's a 截止.
/// Writing 截止/ddl forces 截止, 提醒 forces 提醒. Everything else is the title.
struct QuickParse: Equatable {
    var title = ""
    var tagNames: [String] = []
    var priorityID: String?
    var columnID: String?
    var date: Date?
    var hasTime = false
    var dateKind: DateKind = .deadline

    init(_ text: String, board: Board, now: Date = Date()) {
        var rest = " " + text + " "
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        // Removes the first match of a regex and returns its capture groups.
        func take(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)) else { return nil }
            let groups = (0..<m.numberOfRanges).map { i -> String in
                guard let r = Range(m.range(at: i), in: rest) else { return "" }
                return String(rest[r])
            }
            rest.replaceSubrange(Range(m.range, in: rest)!, with: " ")
            return groups
        }

        // Tags, priority, column.
        while let g = take(#"(?<=\s)#(\S+)"#) { tagNames.append(g[1]) }
        if let g = take(#"(?<=\s)[!！](\S+)"#) {
            let key = g[1]
            if let n = Int(key), n >= 1, n <= board.priorities.count {
                priorityID = board.priorities[n - 1].id
            } else {
                priorityID = board.priorities.first { $0.name == key || (!$0.icon.isEmpty && $0.icon == key) }?.id
                    ?? board.priorities.first { $0.name.hasPrefix(key) }?.id
            }
        }
        if let g = take(#"(?<=\s)[@＠](\S+)"#) {
            columnID = board.columns.first { $0.name == g[1] }?.id ?? board.columns.first { $0.name.hasPrefix(g[1]) }?.id
        }

        // Kind keywords.
        if take(#"截止|ddl|DDL|due"#) != nil { dateKind = .deadline }
        let forcedReminder = take(#"提醒"#) != nil

        // Date.
        let weekdayIndex: [String: Int] = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]
        var day: Date?
        if let g = take(#"(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})[日号]?"#) {
            day = cal.date(from: DateComponents(year: Int(g[1]), month: Int(g[2]), day: Int(g[3])))
        } else if let g = take(#"(\d{1,2})月(\d{1,2})[日号]?"#) ?? take(#"(?<=\s)(\d{1,2})/(\d{1,2})(?=\s)"#) {
            var c = DateComponents(year: cal.component(.year, from: today), month: Int(g[1]), day: Int(g[2]))
            if let d = cal.date(from: c), d < today { c.year! += 1 }   // already passed this year
            day = cal.date(from: c)
        } else if let g = take(#"大后天|后天|明天|今天|today|tomorrow"#) {
            let offset = ["今天": 0, "today": 0, "明天": 1, "tomorrow": 1, "后天": 2, "大后天": 3][g[0]] ?? 0
            day = cal.date(byAdding: .day, value: offset, to: today)
        } else if let g = take(#"(下+)?(?:周|星期|礼拜)([一二三四五六日天])"#), let wd = weekdayIndex[g[2]] {
            // Next such weekday (today counts if it is that day); each 下 adds a week.
            var d = today
            while cal.component(.weekday, from: d) != wd { d = cal.date(byAdding: .day, value: 1, to: d)! }
            let weeksAhead = g[1].count
            if weeksAhead > 0 {
                // 下周X = that weekday in next calendar week.
                let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: today)!.start
                let target = cal.date(byAdding: .weekOfYear, value: weeksAhead, to: thisWeekStart)!
                d = cal.date(byAdding: .day, value: (wd - cal.component(.weekday, from: target) + 7) % 7, to: target)!
            }
            day = d
        }

        // Time.
        var hour: Int?, minute = 0
        if let g = take(#"(上午|早上|早|中午|下午|晚上|傍晚|凌晨)?\s*(\d{1,2})[点:：时](半|\d{1,2})?分?"#) {
            hour = Int(g[2])
            minute = g[3] == "半" ? 30 : Int(g[3]) ?? 0
            if let h = hour, ["下午", "晚上", "傍晚"].contains(g[1]), h < 12 { hour = h + 12 }
            if let h = hour, g[1] == "中午", h < 11 { hour = h + 12 }
        }
        if let h = hour, h < 24, minute < 60 {
            hasTime = true
            var base = day ?? today
            var withTime = cal.date(bySettingHour: h, minute: minute, second: 0, of: base)!
            if day == nil, withTime < now {   // a bare time that's already passed means tomorrow
                base = cal.date(byAdding: .day, value: 1, to: base)!
                withTime = cal.date(bySettingHour: h, minute: minute, second: 0, of: base)!
            }
            date = withTime
            dateKind = .reminder
        } else {
            date = day
        }
        if forcedReminder, date != nil { dateKind = .reminder }
        if !forcedReminder, text.contains("截止") || text.lowercased().contains("ddl") { dateKind = .deadline }

        title = rest.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
