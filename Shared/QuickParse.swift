import Foundation

/// Parses a quick-add line like "交初稿 明天下午3点 #论文修改 !紧急 @进行中".
///   #标签  → tag (created if it doesn't exist)
///   !名称  → priority (by name, emoji, or position: !1 is the most important)
///   @名称  → status column (name prefix)
///   dates  → 今天/明天/后天/大后天, 周五/星期五/下周三, 10月15日, 10/15, 2026-10-15
///   times  → 下午3点, 3点半, 15:30, 晚上8点20
///   English also works: today/tomorrow, mon…sun, next fri, oct 15, in 3 days, 3pm, 9:30am
/// A date with a time becomes a 提醒 (notifies at that time); without a time it's a 截止.
/// Writing 截止/ddl/due/deadline forces 截止, 提醒/remind forces 提醒. The rest is the title.
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
                let lower = key.lowercased()
                // Built-in English names map to the default levels even if they were renamed.
                let english = ["urgent": "urgent", "high": "high", "medium": "normal", "normal": "normal", "low": "low"]
                priorityID = board.priorities.first { $0.name == key || $0.name.lowercased() == lower || (!$0.icon.isEmpty && $0.icon == key) }?.id
                    ?? english[lower].flatMap { id in board.priorities.first { $0.id == id }?.id }
                    ?? board.priorities.first { $0.name.lowercased().hasPrefix(lower) }?.id
            }
        }
        if let g = take(#"(?<=\s)[@＠](\S+)"#) {
            columnID = board.columns.first { $0.name == g[1] }?.id ?? board.columns.first { $0.name.hasPrefix(g[1]) }?.id
        }

        // Kind keywords.
        if take(#"(?i)截止|\bddl\b|\bdue\b|\bdeadline\b"#) != nil { dateKind = .deadline }
        let forcedReminder = take(#"(?i)提醒|\bremind(?:\s+me)?\b|\breminder\b"#) != nil

        // Date.
        let weekdayIndex: [String: Int] = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7,
                                           "sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        /// The next given weekday (today counts); `weeksAhead` > 0 means that weekday in a later calendar week.
        func weekday(_ wd: Int, weeksAhead: Int) -> Date {
            var d = today
            while cal.component(.weekday, from: d) != wd { d = cal.date(byAdding: .day, value: 1, to: d)! }
            if weeksAhead > 0 {
                let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: today)!.start
                let target = cal.date(byAdding: .weekOfYear, value: weeksAhead, to: thisWeekStart)!
                d = cal.date(byAdding: .day, value: (wd - cal.component(.weekday, from: target) + 7) % 7, to: target)!
            }
            return d
        }
        func monthDay(_ month: Int?, _ dayOfMonth: Int?) -> Date? {
            guard let month, let dayOfMonth else { return nil }
            var c = DateComponents(year: cal.component(.year, from: today), month: month, day: dayOfMonth)
            if let d = cal.date(from: c), d < today { c.year! += 1 }   // already passed this year
            return cal.date(from: c)
        }
        var day: Date?
        if let g = take(#"(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})[日号]?"#) {
            day = cal.date(from: DateComponents(year: Int(g[1]), month: Int(g[2]), day: Int(g[3])))
        } else if let g = take(#"(\d{1,2})月(\d{1,2})[日号]?"#) ?? take(#"(?<=\s)(\d{1,2})/(\d{1,2})(?=\s)"#) {
            day = monthDay(Int(g[1]), Int(g[2]))
        } else if let g = take(#"(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b"#) {
            day = monthDay(months.firstIndex(of: g[1].lowercased()).map { $0 + 1 }, Int(g[2]))
        } else if let g = take(#"(?i)\b(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b"#) {
            day = monthDay(months.firstIndex(of: g[2].lowercased()).map { $0 + 1 }, Int(g[1]))
        } else if let g = take(#"(?i)大后天|后天|明天|今天|\btoday\b|\btonight\b|\btomorrow\b"#) {
            let offset = ["今天": 0, "today": 0, "tonight": 0, "明天": 1, "tomorrow": 1, "后天": 2, "大后天": 3][g[0].lowercased()] ?? 0
            day = cal.date(byAdding: .day, value: offset, to: today)
        } else if let g = take(#"(?i)\bin\s+(\d{1,3})\s+days?\b"#), let n = Int(g[1]) {
            day = cal.date(byAdding: .day, value: n, to: today)
        } else if let g = take(#"(下+)?(?:周|星期|礼拜)([一二三四五六日天])"#), let wd = weekdayIndex[g[2]] {
            // Next such weekday (today counts if it is that day); each 下 adds a week.
            day = weekday(wd, weeksAhead: g[1].count)
        } else if let g = take(#"(?i)\b(next\s+)?(mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:r|rs|rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b"#),
                  let wd = weekdayIndex[String(g[2].lowercased().prefix(3))] {
            day = weekday(wd, weeksAhead: g[1].isEmpty ? 0 : 1)
        }

        // Time.
        var hour: Int?, minute = 0
        if let g = take(#"(?i)(?:\bat\s+)?\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#), var h = Int(g[1]) {
            if g[3].lowercased() == "pm", h < 12 { h += 12 }
            if g[3].lowercased() == "am", h == 12 { h = 0 }
            hour = h
            minute = Int(g[2]) ?? 0
        } else if let g = take(#"(?i)\bnoon\b"#), !g.isEmpty {
            hour = 12
        } else if let g = take(#"(?i)\bat\s+(\d{1,2})(?::(\d{2}))?\b"#) {
            hour = Int(g[1])
            minute = Int(g[2]) ?? 0
        } else if let g = take(#"(上午|早上|早|中午|下午|晚上|傍晚|凌晨)?\s*(\d{1,2})[点:：时](半|\d{1,2})?分?"#) {
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
        let lowered = text.lowercased()
        if !forcedReminder, text.contains("截止") || lowered.contains("ddl") || lowered.contains("deadline") || lowered.range(of: #"\bdue\b"#, options: .regularExpression) != nil {
            dateKind = .deadline
        }

        title = rest.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
