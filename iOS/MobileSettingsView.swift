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
