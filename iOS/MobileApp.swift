import SwiftUI
import UserNotifications

// The iPhone app. It shares the data model, merging, storage and the store with the Mac
// app (Shared/, Core/); only the screens are its own.

@main
struct BestPlannerMobileApp: App {
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) private var delegate
    @StateObject private var store: BoardStore

    init() {
        // The iCloud folder must be reopened before the store reads the data.
        FolderAccess.restore()
        _store = StateObject(wrappedValue: BoardStore.shared)
    }

    var body: some Scene {
        WindowGroup {
            MobileBoardView()
                .environmentObject(store)
        }
    }
}

/// Sets the notification delegate before launch finishes, so tapping a reminder that
/// started the app still opens its task.
final class MobileAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { ReminderScheduler.shared.start() }
        return true
    }
}

/// The iCloud Drive folder shared with the Mac ("Best Planner"). iOS only lets the app
/// open it after the user picks it once; a bookmark reopens it on later launches.
enum FolderAccess {
    private static let key = "iCloudFolderBookmark"
    /// For the diagnostics in Settings.
    nonisolated(unsafe) static var accessGranted: Bool?
    nonisolated(unsafe) static var bookmarkWasStale = false

    static func restore() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return
        }
        accessGranted = url.startAccessingSecurityScopedResource()
        bookmarkWasStale = stale
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: key) }
        PlannerStorage.pickedFolder = url
    }

    /// Connects the picked folder (from the Files picker) and remembers it.
    @MainActor
    static func connect(_ url: URL, store: BoardStore) throws {
        accessGranted = url.startAccessingSecurityScopedResource()
        let bookmark = try url.bookmarkData()
        try store.connectFolder(url)
        UserDefaults.standard.set(bookmark, forKey: key)
    }

    @MainActor
    static func disconnect(store: BoardStore) {
        store.disconnectFolder()
        UserDefaults.standard.removeObject(forKey: key)
    }

    static var folderName: String? { PlannerStorage.pickedFolder?.lastPathComponent }
}
