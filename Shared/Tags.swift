import SwiftUI

// MARK: - Tag model

enum TagShape: String, Codable, CaseIterable, Identifiable {
    case capsule, rounded, square, tab, leaf, cutCorner, flag, arrow, chevron, ribbon,
         slant, hexagon, ticket, folded, bubble, scallop, bracket, underline, dot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capsule: L("胶囊")
        case .rounded: L("圆角")
        case .square: L("方角")
        case .tab: L("文件夹")
        case .leaf: L("叶子")
        case .cutCorner: L("切角")
        case .flag: L("吊牌")
        case .arrow: L("箭头")
        case .chevron: L("流程")
        case .ribbon: L("缎带")
        case .slant: L("斜角")
        case .hexagon: L("六边形")
        case .ticket: L("票券")
        case .folded: L("折角")
        case .bubble: L("气泡")
        case .scallop: L("花边")
        case .bracket: L("括号")
        case .underline: L("下划线")
        case .dot: L("圆点")
        }
    }

    var shape: AnyShape {
        switch self {
        case .capsule, .dot: AnyShape(Capsule())
        case .rounded: AnyShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .square, .underline: AnyShape(Rectangle())
        case .tab: AnyShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6, style: .continuous))
        case .leaf: AnyShape(UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 2,
                                                    bottomTrailingRadius: 9, topTrailingRadius: 2, style: .continuous))
        case .cutCorner: AnyShape(CutCornerShape())
        case .flag: AnyShape(PointedTagShape())
        case .arrow: AnyShape(ArrowShape())
        case .chevron: AnyShape(ChevronShape())
        case .ribbon: AnyShape(RibbonShape())
        case .slant: AnyShape(SlantShape())
        case .hexagon: AnyShape(HexagonShape())
        case .ticket: AnyShape(TicketShape())
        case .folded: AnyShape(FoldedCornerShape())
        case .bubble: AnyShape(BubbleShape())
        case .scallop: AnyShape(ScallopShape())
        case .bracket: AnyShape(BracketShape())
        }
    }

    /// Shapes drawn as lines only: no automatic background.
    var isLineOnly: Bool { self == .underline || self == .dot || self == .bracket }

    /// Extra room so text doesn't run into pointed, notched or tailed parts.
    func extraPadding(small: Bool) -> EdgeInsets {
        let u: CGFloat = small ? 3 : 4
        switch self {
        case .flag: return EdgeInsets(top: 0, leading: u + 1, bottom: 0, trailing: 0)
        case .arrow: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: u + 2)
        case .chevron: return EdgeInsets(top: 0, leading: u + 1, bottom: 0, trailing: u + 2)
        case .ribbon: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: u + 1)
        case .slant, .hexagon: return EdgeInsets(top: 0, leading: u, bottom: 0, trailing: u)
        case .ticket, .leaf, .bracket: return EdgeInsets(top: 0, leading: u - 1, bottom: 0, trailing: u - 1)
        case .cutCorner: return EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1)
        case .folded: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: u)
        case .bubble: return EdgeInsets(top: 0, leading: 0, bottom: 3, trailing: 0)
        case .scallop: return EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2)
        default: return EdgeInsets()
        }
    }
}

enum TagStyle: String, Codable, CaseIterable, Identifiable {
    case soft, solid, outline, duotone, gradient, neon, shadow, plain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft: L("浅色")
        case .solid: L("实心")
        case .outline: L("描边")
        case .duotone: L("双色")
        case .gradient: L("渐变")
        case .neon: L("霓虹")
        case .shadow: L("投影")
        case .plain: L("纯文字")
        }
    }

    /// Styles that draw a border by default (when the border is set to 自动).
    var hasDefaultBorder: Bool { self == .outline || self == .duotone || self == .neon }
    /// Styles with a strong fill, so text switches to black/white for contrast.
    var hasStrongFill: Bool { self == .solid || self == .gradient || self == .shadow }
}

enum TagBorder: String, Codable, CaseIterable, Identifiable {
    case auto, none, solid, dashed, dotted, double, dashDot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: L("自动")
        case .none: L("无")
        case .solid: L("实线")
        case .dashed: L("虚线")
        case .dotted: L("点线")
        case .double: L("双线")
        case .dashDot: L("点划线")
        }
    }
}

enum TagBorderWidth {
    static let options: [(value: Double, title: String)] = [
        (0.5, L("极细")), (1, L("细")), (1.5, L("中")), (2, L("粗")), (3, L("特粗")),
    ]
}

struct ResolvedBorder {
    let color: Color
    let pattern: TagBorder
    let width: CGFloat

    var strokeStyle: StrokeStyle {
        let w = width
        switch pattern {
        case .dashed: return StrokeStyle(lineWidth: w, dash: [max(3, w * 3), max(2, w * 2)])
        case .dotted: return StrokeStyle(lineWidth: max(w, 1), lineCap: .round, dash: [0.01, max(2.5, w * 2.5)])
        case .dashDot: return StrokeStyle(lineWidth: w, lineCap: .round, dash: [max(4, w * 4), max(2, w * 2), 0.01, max(2, w * 2)])
        default: return StrokeStyle(lineWidth: w)
        }
    }
}

struct Tag: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var colorHex: String
    var shape: TagShape = .capsule
    var style: TagStyle = .soft
    /// Optional emoji shown before the name.
    var icon: String = ""
    /// Optional overrides; nil means derived from the main color and style.
    var textHex: String?
    var fillHex: String?
    var borderHex: String?
    var border: TagBorder = .auto
    var borderWidth: Double = 1

    var color: Color { Color(hex: colorHex) }

    init(name: String, colorHex: String, shape: TagShape = .capsule, style: TagStyle = .soft, icon: String = "") {
        self.name = name
        self.colorHex = colorHex
        self.shape = shape
        self.style = style
        self.icon = icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#888888"
        shape = (try? c.decodeIfPresent(TagShape.self, forKey: .shape)) ?? .capsule
        style = (try? c.decodeIfPresent(TagStyle.self, forKey: .style)) ?? .soft
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        textHex = try c.decodeIfPresent(String.self, forKey: .textHex)
        fillHex = try c.decodeIfPresent(String.self, forKey: .fillHex)
        borderHex = try c.decodeIfPresent(String.self, forKey: .borderHex)
        border = (try? c.decodeIfPresent(TagBorder.self, forKey: .border)) ?? .auto
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 1
    }

    // MARK: Resolved appearance (override if set, otherwise what the style implies)

    var defaultTextColor: Color {
        style.hasStrongFill && !shape.isLineOnly ? color.contrastingText : color
    }

    /// Plain-color approximation of the automatic fill (for the "自动" preview).
    var defaultFillColor: Color? {
        guard !shape.isLineOnly else { return nil }
        switch style {
        case .soft: return color.opacity(0.18)
        case .duotone: return color.opacity(0.12)
        case .neon: return color.opacity(0.08)
        case .solid, .shadow, .gradient: return color
        case .outline, .plain: return nil
        }
    }

    var fillStyle: AnyShapeStyle? {
        if let fillHex { return AnyShapeStyle(Color(hex: fillHex)) }
        if style == .gradient, !shape.isLineOnly {
            return AnyShapeStyle(LinearGradient(
                colors: [color.mixed(with: .white, 0.35), color, color.mixed(with: .black, 0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return defaultFillColor.map { AnyShapeStyle($0) }
    }

    var textColor: Color { textHex.map(Color.init(hex:)) ?? defaultTextColor }

    var resolvedBorder: ResolvedBorder? {
        let pattern: TagBorder
        switch border {
        case .none: return nil
        case .auto:
            guard style.hasDefaultBorder || shape == .underline || shape == .bracket else { return nil }
            pattern = .solid
        default: pattern = border
        }
        let width = shape == .underline || shape == .bracket ? max(borderWidth, 1.5) : borderWidth
        return ResolvedBorder(color: borderHex.map(Color.init(hex:)) ?? color, pattern: pattern, width: width)
    }

    /// For the "自动" preview of the border color.
    var defaultBorderColor: Color? {
        var t = self
        t.borderHex = nil
        return t.resolvedBorder?.color
    }
}

// MARK: - Presets

/// A matched set of colors for a tag.
struct TagColorPreset: Identifiable {
    let name: String
    let color: String
    var text: String? = nil
    var fill: String? = nil
    var border: String? = nil

    var id: String { name }

    func apply(to tag: inout Tag) {
        tag.colorHex = color
        tag.textHex = text
        tag.fillHex = fill
        tag.borderHex = border
    }

    static let all: [TagColorPreset] = [
        TagColorPreset(name: L("经典蓝"), color: "#3B82F6"),
        TagColorPreset(name: L("樱花粉"), color: "#EC6AA8", text: "#B83280", fill: "#FDE2EF"),
        TagColorPreset(name: L("薄荷绿"), color: "#2BB673", text: "#1D7A4D", fill: "#DFF7EA"),
        TagColorPreset(name: L("日落橙"), color: "#F97316", text: "#C2410C", fill: "#FFEDD5"),
        TagColorPreset(name: L("柠檬黄"), color: "#EAB308", text: "#854D0E", fill: "#FEF9C3"),
        TagColorPreset(name: L("葡萄紫"), color: "#8B5CF6", text: "#6D28D9", fill: "#EDE9FE"),
        TagColorPreset(name: L("珊瑚红"), color: "#EF4444", text: "#B91C1C", fill: "#FEE2E2"),
        TagColorPreset(name: L("湖水青"), color: "#06B6D4", text: "#0E7490", fill: "#CFFAFE"),
        TagColorPreset(name: L("薰衣草"), color: "#A78BFA", text: "#7C3AED", fill: "#F5F3FF", border: "#DDD6FE"),
        TagColorPreset(name: L("森林"), color: "#166534", text: "#166534", fill: "#DCFCE7", border: "#86EFAC"),
        TagColorPreset(name: L("复古"), color: "#92400E", text: "#78350F", fill: "#FEF3C7", border: "#B45309"),
        TagColorPreset(name: L("糖果"), color: "#F472B6", text: "#DB2777", fill: "#FEF3C7", border: "#F9A8D4"),
        TagColorPreset(name: L("玫瑰金"), color: "#B76E79", text: "#8C4A55", fill: "#F8E1E4"),
        TagColorPreset(name: L("金色"), color: "#D4A017", text: "#8A6D00", fill: "#FFF8E1", border: "#D4A017"),
        TagColorPreset(name: L("石墨灰"), color: "#6B7280", text: "#374151", fill: "#F3F4F6"),
        TagColorPreset(name: L("象牙白"), color: "#A8A29E", text: "#44403C", fill: "#FAFAF9", border: "#D6D3D1"),
        TagColorPreset(name: L("午夜蓝"), color: "#1E3A8A", text: "#FDE68A", fill: "#1E3A8A"),
        TagColorPreset(name: L("暗夜黑"), color: "#111827", text: "#F9FAFB", fill: "#111827", border: "#4B5563"),
    ]
}

/// A complete look: shape, style, border and colors in one click.
struct TagLook: Identifiable {
    let name: String
    let shape: TagShape
    let style: TagStyle
    var border: TagBorder = .auto
    var borderWidth: Double = 1
    let color: String
    var text: String? = nil
    var fill: String? = nil
    var borderColor: String? = nil

    var id: String { name }

    func apply(to tag: inout Tag) {
        tag.shape = shape
        tag.style = style
        tag.border = border
        tag.borderWidth = borderWidth
        tag.colorHex = color
        tag.textHex = text
        tag.fillHex = fill
        tag.borderHex = borderColor
    }

    static let all: [TagLook] = [
        TagLook(name: L("便利贴"), shape: .folded, style: .soft, color: "#EAB308", text: "#713F12", fill: "#FEF08A"),
        TagLook(name: L("霓虹灯"), shape: .capsule, style: .neon, borderWidth: 1.5, color: "#22D3EE"),
        TagLook(name: L("印章"), shape: .scallop, style: .outline, border: .double, color: "#DC2626"),
        TagLook(name: L("极简"), shape: .underline, style: .plain, color: "#374151"),
        TagLook(name: L("徽章"), shape: .hexagon, style: .gradient, color: "#9B6CF0"),
        TagLook(name: L("票根"), shape: .ticket, style: .duotone, border: .dashed, color: "#F97316"),
        TagLook(name: L("路牌"), shape: .arrow, style: .solid, color: "#2563EB"),
        TagLook(name: L("嫩芽"), shape: .leaf, style: .soft, color: "#16A34A"),
        TagLook(name: L("对话"), shape: .bubble, style: .soft, color: "#EC4899"),
        TagLook(name: L("书名号"), shape: .bracket, style: .plain, color: "#8B5CF6"),
        TagLook(name: L("金属"), shape: .cutCorner, style: .gradient, border: .solid, color: "#6B7280", borderColor: "#D1D5DB"),
        TagLook(name: L("文件夹"), shape: .tab, style: .shadow, color: "#0EA5E9"),
        TagLook(name: L("流程"), shape: .chevron, style: .solid, color: "#14B8A6"),
        TagLook(name: L("点点"), shape: .rounded, style: .outline, border: .dotted, borderWidth: 1.5, color: "#F43F5E"),
    ]
}

// MARK: - Shapes

/// Luggage tag: pointed left end.
struct PointedTagShape: Shape {
    func path(in r: CGRect) -> Path {
        let notch = min(r.height / 2, 7)
        let radius = min(4, r.height / 4)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + notch, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + notch, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Pointed right end.
struct ArrowShape: Shape {
    func path(in r: CGRect) -> Path {
        let n = min(r.height / 2, 7)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - n, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - n, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Process step: notch on the left, point on the right.
struct ChevronShape: Shape {
    func path(in r: CGRect) -> Path {
        let n = min(r.height / 2, 7)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - n, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - n, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + n, y: r.midY))
        p.closeSubpath()
        return p
    }
}

/// Ribbon: swallowtail notch cut into the right end.
struct RibbonShape: Shape {
    func path(in r: CGRect) -> Path {
        let notch = min(r.height / 2, 6)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - notch, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Parallelogram leaning right.
struct SlantShape: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.height * 0.35, 6)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Stretched hexagon: pointed at both ends.
struct HexagonShape: Shape {
    func path(in r: CGRect) -> Path {
        let n = min(r.height / 2, 6)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + n, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - n, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - n, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + n, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Rectangle with all four corners clipped.
struct CutCornerShape: Shape {
    func path(in r: CGRect) -> Path {
        let c = min(r.height * 0.3, 4.5)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }
}

/// Ticket stub: round notches bitten out of both ends.
struct TicketShape: Shape {
    func path(in r: CGRect) -> Path {
        let n = min(r.height * 0.28, 4)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY - n))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY + n), control: CGPoint(x: r.maxX - n * 1.8, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY + n))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY - n), control: CGPoint(x: r.minX + n * 1.8, y: r.midY))
        p.closeSubpath()
        return p
    }
}

/// Dog-eared top right corner, with the fold drawn in.
struct FoldedCornerShape: Shape {
    func path(in r: CGRect) -> Path {
        let c = min(r.height * 0.4, 6)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        p.move(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY + c))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        return p
    }
}

/// Speech bubble with a small tail at the bottom left.
struct BubbleShape: Shape {
    func path(in r: CGRect) -> Path {
        let tail: CGFloat = 3
        let body = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - tail)
        var p = Path(roundedRect: body, cornerRadius: min(5, body.height / 2), style: .continuous)
        p.move(to: CGPoint(x: r.minX + 5, y: body.maxY - 0.5))
        p.addLine(to: CGPoint(x: r.minX + 4, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 11, y: body.maxY - 0.5))
        p.closeSubpath()
        return p
    }
}

/// Wavy top and bottom edges, like a stamp.
struct ScallopShape: Shape {
    func path(in r: CGRect) -> Path {
        let bump = min(1.8, r.height * 0.12)
        let count = max(2, Int(r.width / 6))
        let step = r.width / CGFloat(count)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + bump))
        for i in 0..<count {
            let x = r.minX + step * CGFloat(i)
            p.addQuadCurve(to: CGPoint(x: x + step, y: r.minY + bump), control: CGPoint(x: x + step / 2, y: r.minY - bump))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bump))
        for i in 0..<count {
            let x = r.maxX - step * CGFloat(i)
            p.addQuadCurve(to: CGPoint(x: x - step, y: r.maxY - bump), control: CGPoint(x: x - step / 2, y: r.maxY + bump))
        }
        p.closeSubpath()
        return p
    }
}

/// Square brackets around the label (lines only).
struct BracketShape: Shape {
    func path(in r: CGRect) -> Path {
        let arm = min(4, r.width / 4)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + arm, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + arm, y: r.maxY))
        p.move(to: CGPoint(x: r.maxX - arm, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - arm, y: r.maxY))
        return p
    }
}

/// A single line along the bottom edge.
struct BottomLineShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

// MARK: - Views

struct TagChip: View {
    let tag: Tag
    var selected = true
    var small = false

    var body: some View {
        chip
            .modifier(TagEffect(style: tag.style, color: tag.color))
            .saturation(selected ? 1 : 0)
            .opacity(selected ? 1 : 0.45)
    }

    private var label: some View {
        HStack(spacing: 3) {
            if !tag.icon.isEmpty { Text(tag.icon) }
            Text(tag.name)
        }
        .scaledFont(small ? .caption2 : .caption,
                    weight: tag.style.hasStrongFill || tag.style == .plain ? .semibold : .regular)
        .foregroundStyle(tag.textColor)
    }

    @ViewBuilder
    private var chip: some View {
        switch tag.shape {
        case .dot:
            HStack(spacing: 4) {
                Circle()
                    .fill(tag.style == .outline ? Color.clear : tag.color)
                    .overlay {
                        if let b = tag.resolvedBorder { Circle().stroke(b.color, style: b.strokeStyle) }
                    }
                    .frame(width: small ? 6 : 8, height: small ? 6 : 8)
                label
            }
        case .underline:
            label
                .padding(.horizontal, 2)
                .padding(.bottom, 3)
                .background(tag.fillHex.map { Rectangle().fill(Color(hex: $0)) })
                .overlay {
                    if let b = tag.resolvedBorder {
                        BottomLineShape().stroke(b.color, style: b.strokeStyle)
                        if b.pattern == .double {
                            BottomLineShape().stroke(b.color, lineWidth: b.width).offset(y: -(b.width + 2))
                        }
                    }
                }
        default:
            let shape = tag.shape.shape
            let extra = tag.shape.extraPadding(small: small)
            label
                .padding(.leading, (small ? 5 : 7) + extra.leading)
                .padding(.trailing, (small ? 5 : 7) + extra.trailing)
                .padding(.top, (small ? 1 : 2) + extra.top)
                .padding(.bottom, (small ? 1 : 2) + extra.bottom)
                .background {
                    if let fill = tag.fillStyle {
                        (tag.shape == .bracket ? AnyShape(Rectangle()) : shape).fill(fill)
                    }
                }
                .overlay {
                    if let b = tag.resolvedBorder {
                        shape.stroke(b.color, style: b.strokeStyle)
                        if b.pattern == .double {
                            // A second, inset outline: the shape redrawn in a smaller frame.
                            shape.stroke(b.color, lineWidth: b.width).padding(b.width + 1.5)
                        }
                    }
                }
        }
    }
}

/// Glow for 霓虹, drop shadow for 投影.
private struct TagEffect: ViewModifier {
    let style: TagStyle
    let color: Color

    func body(content: Content) -> some View {
        switch style {
        case .neon:
            content
                .shadow(color: color.opacity(0.9), radius: 2.5)
                .shadow(color: color.opacity(0.5), radius: 6)
        case .shadow:
            content.shadow(color: .black.opacity(0.3), radius: 2, y: 1.5)
        default:
            content
        }
    }
}

/// A tiny marker for tight spaces (widget rows): the tag's emoji, or its shape.
struct TagMark: View {
    let tag: Tag
    var size: CGFloat = 6

    var body: some View {
        if !tag.icon.isEmpty {
            Text(tag.icon).font(.system(size: size + 3))
        } else if tag.shape == .underline {
            Rectangle().fill(tag.color).frame(width: size * 1.6, height: 2)
        } else if tag.shape == .bracket {
            BracketShape().stroke(tag.color, lineWidth: 1).frame(width: size * 1.6, height: size)
        } else {
            let square: Set<TagShape> = [.square, .rounded, .cutCorner, .dot]
            Group {
                if tag.style == .outline || tag.style == .plain {
                    tag.shape.shape.stroke(tag.color, lineWidth: 1)
                } else {
                    tag.shape.shape.fill(tag.color)
                }
            }
            .frame(width: square.contains(tag.shape) ? size : size * 1.8, height: size)
        }
    }
}

extension Color {
    /// Blends toward another color (e.g. white to lighten, black to darken).
    func mixed(with other: Color, _ fraction: Double) -> Color {
        guard let c = rgb, let o = other.rgb else { return self }
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * fraction }
        return Color(.sRGB, red: mix(c.r, o.r), green: mix(c.g, o.g), blue: mix(c.b, o.b))
    }
}
