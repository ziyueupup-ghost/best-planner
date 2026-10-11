import AppKit
import SwiftUI

// App-wide font size. macOS has no Dynamic Type for apps, so every text style is
// mapped to a point size and multiplied by the user's scale (stored in UserDefaults).

enum FontScale {
    static let storageKey = "fontScale"
    static let presets: [(value: Double, title: String)] = [
        (0.85, L("特小")), (0.92, L("小")), (1.0, L("标准")), (1.15, L("大")), (1.3, L("特大")), (1.45, L("超大")), (1.6, L("巨大")),
    ]
    static let range: ClosedRange<Double> = 0.8...1.8
    static let step = 0.1

    static func clamped(_ v: Double) -> Double {
        min(max((v * 100).rounded() / 100, range.lowerBound), range.upperBound)
    }

    static func title(for v: Double) -> String {
        presets.first { abs($0.value - v) < 0.001 }?.title ?? "\(Int((v * 100).rounded()))%"
    }

    /// macOS default point sizes for each text style.
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption: 10
        case .caption2: 10
        @unknown default: 13
        }
    }

    static func font(_ style: Font.TextStyle, scale: CGFloat, weight: Font.Weight? = nil,
                     monospacedDigit: Bool = false) -> Font {
        var f = Font.system(size: baseSize(style) * scale,
                            weight: weight ?? (style == .headline ? .semibold : .regular))
        if monospacedDigit { f = f.monospacedDigit() }
        return f
    }
}

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var fontScale: CGFloat {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.fontScale) private var scale
    let style: Font.TextStyle
    var weight: Font.Weight?
    var monospacedDigit = false

    func body(content: Content) -> some View {
        content.font(FontScale.font(style, scale: scale, weight: weight, monospacedDigit: monospacedDigit))
    }
}

extension View {
    /// Like `.font(.caption)`, but follows the app's font size setting.
    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, monospacedDigit: Bool = false) -> some View {
        modifier(ScaledFont(style: style, weight: weight, monospacedDigit: monospacedDigit))
    }
}

/// Applies the saved font size to a window or sheet: sets the scale for `scaledFont`,
/// the default body font for unstyled text, and a matching control size.
struct AppFontSize: ViewModifier {
    @AppStorage(FontScale.storageKey) private var stored = 1.0

    func body(content: Content) -> some View {
        let scale = CGFloat(FontScale.clamped(stored))
        content
            .environment(\.fontScale, scale)
            .font(FontScale.font(.body, scale: scale))
            .controlSize(scale >= 1.3 ? .large : scale <= 0.88 ? .small : .regular)
    }
}

extension View {
    func appFontSize() -> some View { modifier(AppFontSize()) }
}

extension FontScale {
    /// Size for a sheet designed at `width`×`height` (100% font): grows with the font
    /// size but stays inside the main window (down to a usable minimum), so neither large
    /// fonts nor a small window clip it.
    @MainActor
    static func sheetSize(width: CGFloat, height: CGFloat, scale: CGFloat) -> CGSize {
        let window = NSApp.mainWindow?.frame.size ?? NSApp.windows.first?.frame.size ?? CGSize(width: 1400, height: 1000)
        return CGSize(width: max(380, min(width * scale, window.width - 40)),
                      height: max(320, min(height * scale, window.height - 60)))
    }
}
