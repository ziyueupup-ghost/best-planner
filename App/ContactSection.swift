import AppKit
import SwiftUI

/// "联系人 / 合作人" in the task editor: the task's contacts as chips (click one to edit
/// its email and phone, × to remove), and a field to add someone — pick from everyone
/// used before, or type a new name and press Return.
struct ContactSection: View {
    @EnvironmentObject private var store: BoardStore
    @Binding var contactIDs: [String]
    @State private var newName = ""
    @State private var editing: String?

    private var chosen: [Contact] { contactIDs.compactMap { store.board.contact($0) } }
    private var suggestions: [Contact] {
        let q = newName.trimmingCharacters(in: .whitespaces)
        return store.board.contactsByUse
            .filter { !contactIDs.contains($0.id) }
            .filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.email.localizedCaseInsensitiveContains(q) }
            .prefix(12).map { $0 }
    }

    var body: some View {
        Section(L("联系人 / 合作人")) {
            if !chosen.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(chosen) { c in
                        HStack(spacing: 4) {
                            Button {
                                editing = c.id
                            } label: {
                                Label(c.name, systemImage: "person.crop.circle")
                            }
                            .buttonStyle(.plain)
                            .help(detail(c))
                            .popover(isPresented: Binding(get: { editing == c.id }, set: { if !$0 { editing = nil } })) {
                                ContactEditor(contactID: c.id)
                            }
                            Button {
                                contactIDs.removeAll { $0 == c.id }
                            } label: {
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                            }
                            .buttonStyle(.borderless)
                            .help(L("从这个任务移除（通讯录里还会保留）"))
                        }
                        .scaledFont(.callout)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Image(systemName: "person.badge.plus").foregroundStyle(.secondary)
                TextField(L("联系人"), text: $newName, prompt: Text(L("输入名字，回车添加；或点下面用过的人")))
                    .labelsHidden()
                    .onSubmit(addTyped)
            }
            if !suggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions) { c in
                        Button {
                            contactIDs.append(c.id)
                            newName = ""
                        } label: {
                            Text("+ \(c.name)")
                                .scaledFont(.caption)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(detail(c))
                    }
                }
            }
        }
    }

    private func detail(_ c: Contact) -> String {
        ([c.name] + [c.email, c.phone].filter { !$0.isEmpty }).joined(separator: "\n")
    }

    private func addTyped() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let contact = store.addContact(named: name)
        if !contactIDs.contains(contact.id) { contactIDs.append(contact.id) }
        newName = ""
    }
}

/// Name, email and phone of one contact (shared by every task that has them).
struct ContactEditor: View {
    @EnvironmentObject private var store: BoardStore
    let contactID: String

    private func binding(_ key: WritableKeyPath<Contact, String>) -> Binding<String> {
        Binding(get: { store.board.contact(contactID)?[keyPath: key] ?? "" },
                set: { value in
                    guard var c = store.board.contact(contactID) else { return }
                    c[keyPath: key] = value
                    store.updateContact(c)
                })
    }

    var body: some View {
        let c = store.board.contact(contactID)
        VStack(alignment: .leading, spacing: 10) {
            TextField(L("名字"), text: binding(\.name))
                .textFieldStyle(.roundedBorder)
                .font(.headline)
            HStack {
                Image(systemName: "envelope").frame(width: 18)
                TextField(L("邮箱"), text: binding(\.email))
                    .textFieldStyle(.roundedBorder)
                if let email = c?.email.trimmingCharacters(in: .whitespaces), !email.isEmpty {
                    Button(L("发邮件")) { MailComposer.compose(to: [email]) }
                        .help(L("用 Outlook 写新邮件"))
                }
            }
            HStack {
                Image(systemName: "phone").frame(width: 18)
                TextField(L("电话"), text: binding(\.phone))
                    .textFieldStyle(.roundedBorder)
                if let phone = c?.phone.filter({ $0.isNumber || $0 == "+" }), !phone.isEmpty,
                   let url = URL(string: "tel:\(phone)") {
                    Button(L("拨打")) { NSWorkspace.shared.open(url) }
                }
            }
            Text(L("改这里会更新所有用到这个人的任务。"))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320)
    }
}

/// A contact's name on a task card: click it for their email and phone, ready to use.
struct ContactNameButton: View {
    let contact: Contact
    @State private var showing = false

    var body: some View {
        Button(contact.name) { showing = true }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .popover(isPresented: $showing, arrowEdge: .bottom) { ContactQuickView(contact: contact) }
    }
}

/// Email or call a contact (from a task card).
private struct ContactQuickView: View {
    let contact: Contact

    private var email: String { contact.email.trimmingCharacters(in: .whitespaces) }
    private var phone: String { contact.phone.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(contact.name, systemImage: "person.crop.circle.fill").font(.headline)
            if email.isEmpty && phone.isEmpty {
                Text(L("还没有邮箱和电话，可以在任务编辑窗口里点他的名字填写。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !email.isEmpty {
                HStack {
                    Image(systemName: "envelope").frame(width: 18)
                    Text(email).textSelection(.enabled).fixedSize()
                    Spacer()
                    copyButton(email)
                    Button(L("发邮件")) { MailComposer.compose(to: [email]) }
                        .help(L("用 Outlook 写新邮件"))
                }
            }
            if !phone.isEmpty {
                HStack {
                    Image(systemName: "phone").frame(width: 18)
                    Text(phone).textSelection(.enabled).fixedSize()
                    Spacer()
                    copyButton(phone)
                    if let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                        Button(L("拨打")) { NSWorkspace.shared.open(url) }
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 330, idealWidth: 420, maxWidth: 520)
        .fixedSize()
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help(L("复制"))
    }
}
