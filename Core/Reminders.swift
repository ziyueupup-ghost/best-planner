#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import UserNotifications

/// Schedules notifications (macOS and iOS) for tasks: 提醒 dates at their exact time, and 截止
/// dates at 9:00 on the day. Rebuilt from the board after every save, so editing or
/// completing a task updates its notifications. Clicking one opens the task.
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    /// A task to open once the board window exists (when a notification launched the app).
    var pendingOpenTaskID: String?

    private let center = UNUserNotificationCenter.current()
    /// macOS keeps at most 64 pending notifications per app.
    private let limit = 60

    func start() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { NSLog("Planner: notification permission error: \(error)") }
            NSLog("Planner: notifications \(granted ? "allowed" : "not allowed")")
        }
    }

    func reschedule(_ board: Board) {
        let now = Date()
        var upcoming: [(date: Date, id: String, content: UNMutableNotificationContent)] = []
        for task in board.tasks where !board.isDone(task) && !task.notificationsOff {
            for d in task.dates {
                let fire: Date
                let content = UNMutableNotificationContent()
                switch d.kind {
                case .reminder:
                    fire = d.date
                    content.title = L("⏰ 提醒")
                case .deadline:
                    fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d.date) ?? d.date
                    content.title = L("📌 今天截止")
                default:
                    continue
                }
                guard fire > now else { continue }
                content.body = d.note.isEmpty ? task.title : "\(task.title)\n\(d.note)"
                content.sound = .default
                content.userInfo = ["taskID": task.id]
                upcoming.append((fire, "task-\(task.id)-\(d.id)", content))
            }
            // Dated subtasks: 9:00 on the day.
            for s in task.subtasks where !s.isDone {
                guard let day = s.date,
                      let fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day), fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = L("📌 子任务今天到期")
                content.body = "\(task.title)：\(s.title)"
                content.sound = .default
                content.userInfo = ["taskID": task.id]
                upcoming.append((fire, "sub-\(task.id)-\(s.id)", content))
            }
        }
        upcoming.sort { $0.date < $1.date }
        center.removeAllPendingNotificationRequests()
        for item in upcoming.prefix(limit) {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: item.id, content: item.content, trigger: trigger))
        }
        NSLog("Planner: scheduled \(min(upcoming.count, limit)) notification(s)")
    }

    // Show banners even while the app is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let taskID = response.notification.request.content.userInfo["taskID"] as? String
        Task { @MainActor in
            #if os(macOS)
            NSApp.activate(ignoringOtherApps: true)
            #endif
            if let taskID {
                self.pendingOpenTaskID = taskID
                NotificationCenter.default.post(name: .openTaskRequested, object: taskID)
            }
            completionHandler()
        }
    }
}

extension Notification.Name {
    /// Asks the board to open a task's editor (object: the task id).
    static let openTaskRequested = Notification.Name("PlannerOpenTaskRequested")
}
