import SwiftUI

/// The toolbar's 云同步 popover: sign in to the Best Planner server, see the sync status,
/// open the web version.
struct CloudSyncView: View {
    @ObservedObject private var cloud = CloudSync.shared
    @State private var email = ""
    @State private var password = ""
    @State private var invite = ""
    @State private var signUp = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("云同步"), systemImage: cloud.symbol).font(.headline)
            if cloud.isSignedIn { signedIn } else { signInForm }
            Divider()
            Button {
                NSWorkspace.shared.open(CloudSync.webURL)
            } label: {
                Label(L("打开网页版"), systemImage: "safari")
            }
            .buttonStyle(.link)
            Text(L("手机上用 Safari 打开网页版，点分享 →「添加到主屏幕」，就能像 App 一样用。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320)
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(L("账号"), value: cloud.email ?? "")
            Text(cloud.statusText)
                .font(.callout)
                .foregroundStyle(cloud.isFailing ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("立即同步")) { cloud.syncSoon() }
                Spacer()
                Button(L("退出登录"), role: .destructive) { cloud.signOut() }
            }
        }
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(signUp ? L("注册一个账号，手机、电脑和网页都能用。") : L("登录后，这台电脑和网页版、其他设备上的任务会自动同步（iCloud 同步照常）。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(L("账号（邮箱或用户名）"), text: $email)
                .textContentType(.username)
            SecureField(signUp ? L("密码（至少 8 位）") : L("密码"), text: $password)
                .textContentType(signUp ? .newPassword : .password)
            if signUp {
                TextField(L("邀请码"), text: $invite)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Button(signUp ? L("已经有账号？登录") : L("还没有账号？注册")) {
                    signUp.toggle()
                    error = nil
                }
                .buttonStyle(.link)
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button(signUp ? L("注册") : L("登录"), action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || email.isEmpty || password.isEmpty || (signUp && invite.isEmpty))
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func submit() {
        working = true
        error = nil
        Task {
            do {
                try await cloud.signIn(email: email, password: password, invite: signUp ? invite : nil, signUp: signUp)
                password = ""
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

extension CloudSync {
    var symbol: String {
        switch status {
        case .off: "icloud.slash"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .synced: "checkmark.icloud"
        case .failed: "exclamationmark.icloud"
        }
    }

    var isFailing: Bool { if case .failed = status { return true }; return false }

    var statusText: String {
        switch status {
        case .off: L("还没有登录")
        case .syncing: L("同步中…")
        case .synced(let date): L("已同步（\(date.formatted(date: .omitted, time: .shortened))）")
        case .failed(let message): L("同步失败，会自动重试：\(message)")
        }
    }
}
