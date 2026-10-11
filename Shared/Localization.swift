import Foundation

// Chinese / English.
//
// UI text is written in Chinese in the source and wrapped in L("…"). In English, L looks
// the text up in `English.table` (Shared/English.swift). Interpolated values become "{}"
// in the lookup key, e.g. L("已选 \(n) 项") uses the key "已选 {} 项" and the English
// "{} selected". Use "{0}", "{1}" in a translation to reorder values. A key may end in
// "|context" when the same Chinese needs different English (L("完成|history") shows 完成
// in Chinese; buttons use plain L("完成") = "Done").
//
// The language is stored in a small file next to the data, so the app and the widget
// (a separate, sandboxed process) always agree. Without that file the system language
// decides: Chinese systems get Chinese, everything else English.

enum AppLanguage: String, CaseIterable {
    case system, chinese = "zh", english = "en"

    private static var fileURL: URL {
        PlannerStorage.localDirectory.appendingPathComponent("language")
    }

    /// The user's choice (system = follow macOS).
    static var choice: AppLanguage {
        let raw = (try? String(contentsOf: fileURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Fixed for the life of the process (switching asks for a relaunch).
    static let isEnglish: Bool = {
        switch choice {
        case .english: return true
        case .chinese: return false
        case .system: return !(Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
        }
    }()

    /// Saves the choice for the app and the widget, and tells macOS which language the
    /// app's own menus (Edit, Window…) should use. Takes effect after relaunch.
    static func set(_ language: AppLanguage) {
        try? FileManager.default.createDirectory(at: PlannerStorage.localDirectory, withIntermediateDirectories: true)
        if language == .system {
            try? FileManager.default.removeItem(at: fileURL)
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            try? language.rawValue.write(to: fileURL, atomically: true, encoding: .utf8)
            UserDefaults.standard.set([language == .english ? "en" : "zh-Hans"], forKey: "AppleLanguages")
        }
    }
}

/// Text with its interpolated values kept apart, so it can be looked up as a template.
struct LText: ExpressibleByStringInterpolation {
    var key: String
    var args: [String]

    init(stringLiteral value: String) {
        key = value
        args = []
    }

    init(stringInterpolation: Interpolation) {
        key = stringInterpolation.key
        args = stringInterpolation.args
    }

    struct Interpolation: StringInterpolationProtocol {
        var key = ""
        var args: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {}

        mutating func appendLiteral(_ literal: String) { key += literal }

        mutating func appendInterpolation<T>(_ value: T) {
            key += "{}"
            args.append(String(describing: value))
        }
    }
}

/// The text in the app's language.
func L(_ text: LText) -> String {
    let chinese = text.key.split(separator: "|", maxSplits: 1).first.map(String.init) ?? text.key
    let template = AppLanguage.isEnglish ? (English.table[text.key] ?? chinese) : chinese
    return fill(template, text.args)
}

private func fill(_ template: String, _ args: [String]) -> String {
    guard !args.isEmpty else { return template }
    var out = template
    if out.contains("{0}") {
        for (i, a) in args.enumerated() { out = out.replacingOccurrences(of: "{\(i)}", with: a) }
        return out
    }
    for a in args {
        guard let r = out.range(of: "{}") else { break }
        out.replaceSubrange(r, with: a)
    }
    return out
}
