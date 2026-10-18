import Foundation
import PrayerKit
import UserNotifications

@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var pendingWork: Task<Void, Never>?

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Replaces every pending request this app owns with `plan`. Calls run
    /// in order so an older plan never re-adds requests after a newer one.
    func replace(with plan: [PlannedNotification]) {
        let previous = pendingWork
        pendingWork = Task {
            await previous?.value
            await apply(plan)
        }
    }

    private func apply(_ plan: [PlannedNotification]) async {
        let pending = await center.pendingNotificationRequests()
        let owned = pending.map(\.identifier).filter { $0.hasPrefix(PlannedNotification.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: owned)

        let calendar = Calendar.current
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            // A calendar trigger fires at wall-clock time even after sleep,
            // unlike an interval trigger.
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
    }

    // A menu bar app is always frontmost-capable, so show banners anyway.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
