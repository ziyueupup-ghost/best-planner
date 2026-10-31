import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 附件和链接 in the task editor: files (picked or dragged in) and web links.
struct LinksSection: View {
    @Binding var links: [TaskLink]
    @State private var newURL = ""
    @State private var dropTargeted = false

    var body: some View {
        Section {
            ForEach(links) { link in
                LinkRow(link: link) { links.removeAll { $0.id == link.id } }
            }
            HStack {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField(L("网址"), text: $newURL, prompt: Text(L("粘贴网址，回车添加")))
                    .labelsHidden()
                    .onSubmit(addURL)
                Button(L("添加文件…"), action: pickFiles)
            }
        } header: {
            Text(links.isEmpty ? L("附件和链接") : L("附件和链接（\(links.count)）"))
        } footer: {
            Text(L("可以把文件或文件夹直接拖到这里。文件不会被复制，只记住它在电脑上的位置。"))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .listRowBackground(dropTargeted ? Color.accentColor.opacity(0.12) : nil)
    }

    private func addURL() {
        var text = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else { return }
        links.append(TaskLink(title: url.host() ?? text, url: url.absoluteString))
        newURL = ""
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = L("添加")
        if panel.runModal() == .OK { add(panel.urls) }
    }

    private func add(_ urls: [URL]) {
        for url in urls where !links.contains(where: { $0.url == url.absoluteString }) {
            links.append(TaskLink(title: url.isFileURL ? url.lastPathComponent : (url.host() ?? url.absoluteString),
                                  url: url.absoluteString, device: url.isFileURL ? TaskLink.thisDevice : nil))
        }
    }
}

private struct LinkRow: View {
    let link: TaskLink
    let remove: () -> Void

    var body: some View {
        let url = URL(string: link.url)
        let missing = link.isFile && !(url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        HStack(spacing: 8) {
            if link.isFile, let url, !missing {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: link.isFile ? "doc.badge.ellipsis" : "globe")
                    .foregroundStyle(missing ? .red : .secondary)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(link.title).lineLimit(1)
                Text(missing ? L("找不到这个文件（可能被移动或删除了）") : (url.map { $0.isFileURL ? $0.deletingLastPathComponent().path : $0.absoluteString } ?? link.url))
                    .scaledFont(.caption2)
                    .foregroundStyle(missing ? .red : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(L("打开")) { if let url { NSWorkspace.shared.open(url) } }
                .disabled(missing)
            if link.isFile, let url, !missing {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "folder") }
                    .help(L("在访达中显示"))
            }
            Button(action: remove) { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .help(L("移除（不会删除文件）"))
        }
    }
}

/// "打开附件" submenu for a card's right-click menu.
struct OpenLinksMenu: View {
    let links: [TaskLink]

    var body: some View {
        if !links.isEmpty {
            Menu(L("打开附件（\(links.count)）")) {
                ForEach(links) { link in
                    Button(link.title) { if let url = URL(string: link.url) { NSWorkspace.shared.open(url) } }
                }
            }
        }
    }
}
