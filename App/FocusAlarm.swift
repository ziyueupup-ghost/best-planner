import AppKit
import SwiftUI

/// The alarm when a focus period or a break ends: a sound that repeats until dismissed
/// (or for a minute), with a reminder window in the middle of the screen.
@MainActor
final class FocusAlarm {
    static let shared = FocusAlarm()

    static let enabledKey = "focusAlarmOn"
    static let soundKey = "focusAlarmSound"
    /// System sounds (in /System/Library/Sounds), loudest-sounding first.
    static let sounds = ["Glass", "Hero", "Submarine", "Ping", "Funk", "Sosumi", "Purr", "Blow", "Bottle", "Frog", "Morse", "Pop", "Tink", "Basso"]

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var soundName: String { UserDefaults.standard.string(forKey: soundKey) ?? "Glass" }

    private var panel: NSPanel?
    private var repeatTimer: Timer?
    private var stopTimer: Timer?
    private var sound: NSSound?

    private init() {}

    /// Rings (if turned on) and shows the reminder.
    func ring(title: String, message: String) {
        guard FocusAlarm.isEnabled else { NSSound.beep(); return }
        dismiss()
        sound = NSSound(named: NSSound.Name(FocusAlarm.soundName))
        sound?.play()
        // Repeat the sound every 1.5 s; stop by itself after a minute.
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sound?.stop()
                self?.sound?.play()
            }
        }
        stopTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.silence() }
        }
        show(title: title, message: message)
    }

    /// Stops the sound (the reminder stays until closed).
    func silence() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        stopTimer?.invalidate()
        stopTimer = nil
        sound?.stop()
        sound = nil
    }

    func dismiss() {
        silence()
        panel?.orderOut(nil)
        panel = nil
    }

    /// Plays a sound once (choosing one in the settings).
    static func preview(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func show(title: String, message: String) {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = NSHostingView(rootView: FocusAlarmView(title: title, message: message).appFontSize())
        p.center()
        p.orderFrontRegardless()
        panel = p
    }
}

private struct FocusAlarmView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button(L("知道了")) { FocusAlarm.shared.dismiss() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(width: 340, height: 150)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.12)))
    }
}
