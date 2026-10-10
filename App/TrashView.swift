import SwiftUI

/// 最近删除: deleted tasks, restorable for 30 days.
struct TrashView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fontScale) private var fontScale
    @State private var confirmEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("最近删除", systemImage: "trash")
                    .scaledFont(.title2, weight: .bold)
                Spacer()
                Button("清空", role: .destructive) { confirmEmpty = true }
                    .disabled(store.board.trash.isEmpty)
            }
            Text("删除的任务会在这里保留 30 天，恢复后回到原来的状态。")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)

            if store.board.trash.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "trash.slash")
                        .font(.system(size: 32 * fontScale))
                        .foregroundStyle(.tertiary)
                    Text("没有删除的任务").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.board.trash.enumerated()), id: \.element.id) { i, task in
                            row(task)
                                .background(i.isMultiple(of: 2) ? Color.primary.opacity(0.04) : .clear)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: FontScale.sheetSize(width: 560, height: 480, scale: fontScale).width,
               height: FontScale.sheetSize(width: 560, height: 480, scale: fontScale).height)
        .onExitCommand { dismiss() }
        .alert("永久删除全部 \(store.board.trash.count) 个任务？", isPresented: $confirmEmpty) {
            Button("永久删除", role: .destructive) { store.emptyTrash() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空后无法再恢复。")
        }
    }

    private func row(_ task: PlannerTask) -> some View {
        let column = store.board.column(task.columnID)
        let deleted = task.deletedAt ?? Date()
        let daysLeft = max(0, 30 - (Calendar.current.dateComponents([.day], from: deleted, to: Date()).day ?? 0))
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    PriorityMark(level: store.board.priority(of: task))
                    Text(task.title).scaledFont(.body, weight: .medium).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(column.map { $0.icon.isEmpty ? $0.name : "\($0.icon) \($0.name)" } ?? "原状态已删除")
                    Text("·")
                    Text("\(deleted.dayTimeLabel) 删除")
                    Text("·")
                    Text("还剩 \(daysLeft) 天")
                }
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation(.snappy) { store.restore(task.id) }
            } label: {
                Label("恢复", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                withAnimation(.snappy) { store.deleteForever(task.id) }
            } label: {
                Image(systemName: "xmark.bin")
            }
            .help("永久删除")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
