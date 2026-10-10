import SwiftUI

/// A color dot that opens preset swatches, with the system color picker for anything else.
struct ColorSwatchPicker: View {
    @Binding var hex: String
    var palette: [String] = Palette.colors
    @State private var show = false

    var body: some View {
        Button {
            show = true
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .help("选择颜色")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 8), spacing: 6) {
                    ForEach(palette, id: \.self) { c in
                        Button {
                            hex = c
                            show = false
                        } label: {
                            Circle()
                                .fill(Color(hex: c))
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                                .overlay(
                                    Circle().strokeBorder(Color.accentColor, lineWidth: 2.5)
                                        .padding(-3)
                                        .opacity(c.caseInsensitiveCompare(hex) == .orderedSame ? 1 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider()
                HStack {
                    Text("更多颜色").scaledFont(.callout).foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: hex) }, set: { hex = $0.hexString }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
            }
            .padding(12)
            .frame(width: 260)
        }
    }
}
