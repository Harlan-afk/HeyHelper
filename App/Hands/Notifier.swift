import Foundation
import UserNotifications

/// Local notifications: timers, reminders, and "tap to open" when the phone is locked.
enum Notifier {
    static let openURLKey = "openURL"

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func post(title: String, body: String, url: URL? = nil) async {
        await add(title: title, body: body, url: url, trigger: nil)
    }

    static func schedule(inSeconds seconds: Int, title: String, body: String) async {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        await add(title: title, body: body, url: nil, trigger: trigger)
    }

    /// Fires the next time the clock reaches hour:minute.
    static func schedule(hour: Int, minute: Int, title: String, body: String) async {
        var when = DateComponents()
        when.hour = hour
        when.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        await add(title: title, body: body, url: nil, trigger: trigger)
    }

    private static func add(title: String, body: String, url: URL?, trigger: UNNotificationTrigger?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url { content.userInfo = [openURLKey: url.absoluteString] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
