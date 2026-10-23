import AppKit

/// Starts a new email in Outlook (or, without Outlook, the default mail app).
enum MailComposer {
    static let outlookID = "com.microsoft.Outlook"

    static func compose(to addresses: [String], subject: String = "") {
        let to = addresses.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !to.isEmpty else { return }
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = to.joined(separator: ",")
        if !subject.isEmpty { parts.queryItems = [URLQueryItem(name: "subject", value: subject)] }
        guard let url = parts.url else { return }
        if let outlook = NSWorkspace.shared.urlForApplication(withBundleIdentifier: outlookID) {
            NSWorkspace.shared.open([url], withApplicationAt: outlook, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
