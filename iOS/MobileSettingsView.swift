import SwiftUI
import UniformTypeIdentifiers

/// Sync with the Mac (pick the iCloud Drive folder), language, about.
struct MobileSettingsView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var error: String?
    @State private var language = AppLanguage.choice
    @State private var languageChanged = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Where the data actually goes, for tracking down sync problems.
    private var diagnostics: [String] {
        let fm = FileManager.default
        let file = PlannerStorage.fileURL
        func short(_ url: URL) -> String { url.pathComponents.suffix(3).joined(separator: "/") }
        return [
            "folder: \(PlannerStorage.pickedFolder.map(short) ?? "-")",
            "access: \(FolderAccess.accessGranted.map { $0 ? "yes" : "NO" } ?? "-")\(FolderAccess.bookmarkWasStale ? " (stale)" : "")",
            "file exists: \(fm.fileExists(atPath: file.path)) readable: \(fm.isReadableFile(atPath: file.path)) writable: \(fm.isWritableFile(atPath: file.path))",
            "file date: \(PlannerStorage.modificationDate().map { $0.formatted(date: .omitted, time: .standard) } ?? "-")",
            "group: \(PlannerStorage.appGroupContainer != nil ? "yes" : "NO") local: \(short(PlannerStorage.localDirectory))",
            "bundle: \(Bundle.main.bundleIdentifier ?? "-")",
            "copy date: \(PlannerStorage.mirrorModificationDate().map { $0.formatted(date: .omitted, time: .standard) } ?? "-")",
            "save error: \(store.saveError ?? "none")",
        ]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.usesICloud, let name = FolderAccess.folderName {
                        Label(L("正在和 iCloud 云盘「\(name)」文件夹同步"), systemImage: "icloud.fill")
                            .foregroundStyle(.green)
                        Button(L("换一个文件夹…")) { picking = true }
                        Button(L("停止同步（只用这台 iPhone 上的数据）"), role: .destructive) {
                            FolderAccess.disconnect(store: store)
                        }
                    } else {
                        Label(L("现在只保存在这台 iPhone 上"), systemImage: "iphone")
                        Button {
                            picking = true
                        } label: {
                            Label(L("选择 iCloud 云盘里的「Best Planner」文件夹"), systemImage: "folder.badge.plus")
                        }
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                } header: {
                    Text(L("和 Mac 同步"))
                } footer: {
                    Text(L("在 Mac 上打开 iCloud 云盘同步后，iCloud 云盘里会有一个「Best Planner」文件夹。在这里选中它，iPhone 和 Mac 就用同一份数据。文件夹里已经有数据时会用那份数据（这台 iPhone 原来的数据会先备份）。"))
                }

                Section {
                    ForEach(store.board.columns) { c in
                        Toggle(c.icon.isEmpty ? c.name : "\(c.icon) \(c.name)", isOn: Binding(
                            get: { store.board.widgetColumnIDs.contains(c.id) },
                            set: { _ in store.toggleWidgetColumn(c.id) }))
                    }
                    if !store.board.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("只显示带这些标签的任务"))
                            FlowLayout(spacing: 6) {
                                ForEach(store.board.tags) { tag in
                                    Button { store.toggleWidgetTag(tag.id) } label: {
                                        TagChip(tag: tag, selected: store.board.widgetTagIDs.contains(tag.id))
                                            .environment(\.fontScale, MobileStyle.tagScale)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(L("桌面小组件显示"))
                } footer: {
                    Text(L("iPhone 和 Mac 的小组件都按这里显示，两边会同步。状态都不选就按默认显示；标签都不选就显示所有任务。"))
                }

                Section {
                    Picker(L("语言"), selection: $language) {
                        Text(L("跟随系统")).tag(AppLanguage.system)
                        Text("中文").tag(AppLanguage.chinese)
                        Text("English").tag(AppLanguage.english)
                    }
                    .onChange(of: language) { _, value in
                        AppLanguage.set(value)
                        languageChanged = true
                    }
                } footer: {
                    if languageChanged { Text(L("完全关闭再重新打开软件后生效。")) }
                }

                Section {
                    LabeledContent(L("版本"), value: version)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(diagnostics, id: \.self) { Text($0) }
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    LabeledContent(L("任务"), value: "\(store.tasks.count)")
                }
            }
            .navigationTitle(L("设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("完成")) { dismiss() } }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    do {
                        try FolderAccess.connect(url, store: store)
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                case .failure(let failure):
                    error = failure.localizedDescription
                }
            }
        }
    }
}
