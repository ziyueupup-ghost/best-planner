import SwiftUI

/// Which statuses and tags the desktop widgets (Mac and iPhone) show. Opened from the
/// toolbar; changes are saved (and synced) right away.
struct WidgetFilterView: View {
    @EnvironmentObject private var store: BoardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("桌面小组件显示")).scaledFont(.headline)
            Text(L("显示这些状态的任务")).scaledFont(.subheadline).foregroundStyle(.secondary)
            FlowLayout(spacing: 10) {
                ForEach(store.board.columns) { c in
                    Toggle(isOn: Binding(get: { store.board.widgetColumnIDs.contains(c.id) },
                                         set: { _ in store.toggleWidgetColumn(c.id) })) {
                        Text(c.icon.isEmpty ? c.name : "\(c.icon) \(c.name)")
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Divider()
            Text(L("只显示带这些标签的任务")).scaledFont(.subheadline).foregroundStyle(.secondary)
            if store.board.tags.isEmpty {
                Text(L("还没有标签")).scaledFont(.caption).foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(store.board.tags) { tag in
                        Button { store.toggleWidgetTag(tag.id) } label: {
                            TagChip(tag: tag, selected: store.board.widgetTagIDs.contains(tag.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider()
            Text(L("iPhone 和 Mac 的小组件都按这里显示，两边会同步。状态都不选就按默认显示；标签都不选就显示所有任务。"))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 340)
    }
}
