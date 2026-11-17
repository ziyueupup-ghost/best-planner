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
            Text(L("可以把文件或文件夹直接拖到这里。文件不会被复制，只记住它在电脑上的位置。Outlook 的邮件请先拖到访达的某个文件夹（变成 .eml 文件），再拖进来。"))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        // Files, folders, links — and emails dragged out of Outlook or Mail.
        .linkDrop(isTargeted: $dropTargeted) { new in
            links += new.filter { l in !links.contains { $0.url == l.url } }
        }
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

extension TaskLink {
    /// A file or folder on this Mac, or a web address.
    static func from(_ url: URL) -> TaskLink {
        TaskLink(title: url.isFileURL ? url.lastPathComponent : (url.host() ?? url.absoluteString),
                 url: url.absoluteString, device: url.isFileURL ? TaskLink.thisDevice : nil)
    }

    /// What's typed or pasted as a web address ("example.com" gets https://).
    static func web(_ text: String) -> TaskLink? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("/") || text.hasPrefix("~") {   // a pasted path
            return .from(URL(fileURLWithPath: (text as NSString).expandingTildeInPath))
        }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else { return nil }
        return TaskLink(title: url.host() ?? text, url: url.absoluteString)
    }

    var fileURL: URL? { URL(string: url) }
    var fileMissing: Bool { isFile && !(fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false) }
}

/// Lets the user pick files or folders (several at once).
@MainActor
func pickFileLinks() -> [TaskLink] {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.prompt = L("添加")
    return panel.runModal() == .OK ? panel.urls.map(TaskLink.from) : []
}

/// A task's or a subtask's files and links as small chips: click to open (a folder opens
/// in Finder), the folder button shows a file in Finder; right-click to remove.
struct LinkChips: View {
    let links: [TaskLink]
    var remove: ((TaskLink) -> Void)?
    var limit = 3

    var body: some View {
        if !links.isEmpty {
            HStack(spacing: 6) {
                ForEach(links.prefix(limit)) { chip($0) }
                if links.count > limit {
                    Menu(L("还有 \(links.count - limit) 个")) {
                        ForEach(links.dropFirst(limit)) { link in
                            Button(link.title) { open(link) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .scaledFont(.caption)
                }
            }
        }
    }

    private func chip(_ link: TaskLink) -> some View {
        let missing = link.fileMissing
        return HStack(spacing: 3) {
            Button { open(link) } label: {
                // Long names are shortened in the middle ("very long…name.pdf").
                Label(link.title.count > 28 ? String(link.title.prefix(16)) + "…" + String(link.title.suffix(10)) : link.title,
                      systemImage: link.isFile ? (missing ? "doc.badge.ellipsis" : "paperclip") : "link")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help(missing ? L("找不到这个文件（可能被移动或删除了）") : L("打开「\(link.title)」"))
            if link.isFile, !missing, let url = link.fileURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain)
                    .help(L("在访达中显示"))
            }
        }
        .scaledFont(.caption)
        .foregroundStyle(missing ? Color.red : Color.accentColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.08), in: Capsule())
        .contextMenu {
            Button(L("打开")) { open(link) }.disabled(missing)
            if link.isFile, !missing, let url = link.fileURL {
                Button(L("在访达中显示")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            if let remove {
                Divider()
                Button(L("移除（不会删除文件）"), role: .destructive) { remove(link) }
            }
        }
    }

    private func open(_ link: TaskLink) {
        if let url = link.fileURL, !link.fileMissing { NSWorkspace.shared.open(url) }
    }
}

/// 📎: add files / folders or a web address to a task or a subtask.
struct AddLinkButton: View {
    let add: ([TaskLink]) -> Void
    @State private var typing = false
    @State private var text = ""

    var body: some View {
        Menu {
            Button(L("添加文件或文件夹…")) {
                let links = pickFileLinks()
                if !links.isEmpty { add(links) }
            }
            Button(L("添加网址…")) { typing = true }
        } label: {
            Image(systemName: "paperclip")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("添加附件或链接（文件、文件夹、网址）"))
        .popover(isPresented: $typing) {
            HStack {
                TextField(L("网址"), text: $text, prompt: Text(L("粘贴网址，回车添加")))
                    .frame(width: 260)
                    .onSubmit(submit)
                Button(L("添加"), action: submit)
            }
            .padding(10)
        }
    }

    private func submit() {
        if let link = TaskLink.web(text) { add([link]) }
        text = ""
        typing = false
    }
}

// MARK: Dropping files, folders, links and emails

/// Turns what's dropped into links: files and folders (linked where they are), web
/// addresses, and things that only exist once dropped — an email dragged out of Outlook or
/// Mail, an attachment dragged out of a message. Those are saved as files into the 附件
/// folder next to the board (so they sync with it) and linked there.
enum LinkDrop {
    /// Where dropped emails and other dragged-out files are kept.
    static var folder: URL { PlannerStorage.directory.appendingPathComponent("附件", isDirectory: true) }

    @MainActor
    static func receive(_ providers: [NSItemProvider], add: @escaping ([TaskLink]) -> Void, failed: @escaping (String) -> Void) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    DispatchQueue.main.async {
                        if let url { add([TaskLink.from(url)]) } else { saveCopy(provider, add: add, failed: failed) }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    DispatchQueue.main.async {
                        if let url { add([TaskLink.from(url)]) } else { saveCopy(provider, add: add, failed: failed) }
                    }
                }
            } else {
                saveCopy(provider, add: add, failed: failed)
            }
        }
    }

    /// Asks for the dragged thing as a file (an email becomes an .eml) and keeps a copy.
    @MainActor
    private static func saveCopy(_ provider: NSItemProvider, add: @escaping ([TaskLink]) -> Void, failed: @escaping (String) -> Void) {
        let types = provider.registeredTypeIdentifiers
        // Outlook hands an email over as its raw text ("From: … Subject: … MIME-Version"):
        // keep that as an .eml file named after the subject. Anything else as a file.
        if let textType = types.first(where: { UTType($0)?.conforms(to: .text) ?? false }) {
            _ = provider.loadDataRepresentation(forTypeIdentifier: textType) { data, _ in
                let text = data.flatMap { String(data: $0.prefix(20_000), encoding: .utf8) ?? String(data: $0.prefix(20_000), encoding: .isoLatin1) } ?? ""
                let saved = data.flatMap { isEmail(text) ? store($0, name: emailName(text) + ".eml") : nil }
                DispatchQueue.main.async {
                    if let saved { add([TaskLink.from(saved)]) } else { saveFile(provider, add: add, failed: failed) }
                }
            }
        } else {
            saveFile(provider, add: add, failed: failed)
        }
    }

    @MainActor
    private static func saveFile(_ provider: NSItemProvider, add: @escaping ([TaskLink]) -> Void, failed: @escaping (String) -> Void) {
        let types = provider.registeredTypeIdentifiers
        // A whole file (email, document), not text.
        guard let type = types.first(where: { UTType($0).map { !$0.conforms(to: .text) && $0.conforms(to: .data) } ?? false }) else {
            failed(types.joined(separator: ", ")); return
        }
        let suggested = provider.suggestedName
        _ = provider.loadFileRepresentation(forTypeIdentifier: type) { temp, _ in
            var result: URL?
            if let temp {
                let fm = FileManager.default
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                var name = temp.lastPathComponent
                if let suggested, !suggested.isEmpty, !name.contains(suggested) {
                    let ext = temp.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "") : temp.pathExtension
                    name = ext.isEmpty ? suggested : "\(suggested).\(ext)"
                }
                name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                var target = folder.appendingPathComponent(name)
                var n = 2
                while fm.fileExists(atPath: target.path) {
                    let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
                    target = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
                    n += 1
                }
                if (try? fm.copyItem(at: temp, to: target)) != nil { result = target }
            }
            DispatchQueue.main.async {
                if let result { add([TaskLink.from(result)]) } else { failed(types.joined(separator: ", ")) }
            }
        }
    }
}

extension LinkDrop {
    /// Looks like the source of an email (headers at the top).
    static func isEmail(_ text: String) -> Bool {
        let head = text.prefix(8000).lowercased()
        return head.contains("mime-version:") || (head.contains("\nfrom:") || head.hasPrefix("from:")) && head.contains("\nsubject:")
    }

    /// The email's subject (decoded when it's =?utf-8?…?=), for its file name.
    static func emailName(_ text: String) -> String {
        var subject = ""
        var inSubject = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(400) {
            let l = line.trimmingCharacters(in: .newlines)
            if l.isEmpty { break }   // end of the headers
            if inSubject, l.first == " " || l.first == "\t" { subject += " " + l.trimmingCharacters(in: .whitespaces); continue }
            inSubject = l.lowercased().hasPrefix("subject:")
            if inSubject { subject = String(l.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
        }
        subject = decodeHeader(subject)
        let cleaned = subject.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? L("邮件") + " " + Date().formatted(.dateTime.year().month().day().hour().minute()) : String(cleaned.prefix(80))
    }

    /// "=?utf-8?B?…?=" / "=?utf-8?Q?…?=" pieces of a header, decoded.
    private static func decodeHeader(_ s: String) -> String {
        // Spaces between two encoded pieces don't count.
        let s = s.replacingOccurrences(of: "\\?=\\s+=\\?", with: "?==?", options: .regularExpression)
        guard let re = try? NSRegularExpression(pattern: "=\\?([^?]+)\\?([bBqQ])\\?([^?]*)\\?=") else { return s }
        var out = s
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let whole = Range(m.range, in: s), let cs = Range(m.range(at: 1), in: s),
                  let enc = Range(m.range(at: 2), in: s), let body = Range(m.range(at: 3), in: s) else { continue }
            let charset = CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding(String(s[cs]) as CFString))
            var bytes: Data?
            if s[enc].lowercased() == "b" {
                bytes = Data(base64Encoded: String(s[body]))
            } else {
                var d = Data(), chars = Array(String(s[body]).replacingOccurrences(of: "_", with: " ").utf8), i = 0
                while i < chars.count {
                    if chars[i] == UInt8(ascii: "="), i + 2 < chars.count, let v = UInt8(String(bytes: chars[i+1...i+2], encoding: .ascii) ?? "", radix: 16) {
                        d.append(v); i += 3
                    } else { d.append(chars[i]); i += 1 }
                }
                bytes = d
            }
            if let bytes, let text = String(data: bytes, encoding: String.Encoding(rawValue: charset == UInt(kCFStringEncodingInvalidId) ? String.Encoding.utf8.rawValue : charset)) {
                out.replaceSubrange(Range(m.range, in: out) ?? whole, with: text)
            }
        }
        return out
    }

    /// Writes data into the 附件 folder under a name not already taken.
    static func store(_ data: Data, name: String) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var target = folder.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
            target = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return (try? data.write(to: target)) != nil ? target : nil
    }
}

extension View {
    /// Accepts files, folders, web links and emails dragged in from other apps.
    /// `types`: what to accept — by default anything (also emails handed over as text);
    /// in the 日程 just files, folders and web links, so dragging plan rows still works.
    func linkDrop(isTargeted: Binding<Bool>? = nil, types: [UTType] = [.fileURL, .url, .data, .item],
                  add: @escaping ([TaskLink]) -> Void) -> some View {
        modifier(LinkDropModifier(external: isTargeted, types: types, add: add))
    }
}

private struct LinkDropModifier: ViewModifier {
    let external: Binding<Bool>?
    let types: [UTType]
    let add: ([TaskLink]) -> Void
    @State private var targeted = false
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .overlay {
                // Without its own highlight (the editor's section has one), outline the target.
                if targeted && external == nil {
                    RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2).allowsHitTesting(false)
                }
            }
            .onDrop(of: types, isTargeted: Binding(get: { targeted }, set: { targeted = $0; external?.wrappedValue = $0 })) { providers in
                LinkDrop.receive(providers, add: add) { types in failure = types }
                return true
            }
            .alert(L("没能加进来"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(L("好")) { failure = nil }
            } message: {
                Text(L("这个内容没法存成附件。可以先把它拖到桌面变成文件，再拖进来。") + "\n\n(\(failure ?? ""))")
            }
    }
}
