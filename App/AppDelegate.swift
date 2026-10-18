import AppKit

/// Sets the notification delegate before launch finishes, so a click on a notification
/// that started the app is still delivered.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { ReminderScheduler.shared.start() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            GlobalHotKey.shared.register()
            Updater.checkOnLaunch()
            WidgetRefresher.afterUpdate()
        }
    }
}
