import SwiftUI

/// A progress flag as shown on cards: a small tinted capsule, "😣 卡住了".
struct FlagChip: View {
    let flag: ProgressFlag
    /// Only the emoji (or a dot), for tight places like the widget.
    var compact = false

    var body: some View {
        if compact {
            if flag.icon.isEmpty {
                Circle().fill(flag.color).frame(width: 7, height: 7)
            } else {
                Text(flag.icon).font(.caption2)
            }
        } else {
            HStack(spacing: 3) {
                if !flag.icon.isEmpty { Text(flag.icon) }
                Text(flag.name).fontWeight(.medium)
            }
            .scaledFont(.caption)
            .foregroundStyle(flag.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(flag.color.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(flag.color.opacity(0.35)))
        }
    }
}
