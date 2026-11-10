import Foundation
import UserNotifications

protocol ReminderScheduler: AnyObject {
    // skipToday – урок сегодня уже засчитан, сегодняшнее напоминание не нужно
    func schedule(hour: Int, minute: Int, skipToday: Bool)
    func cancel()
}

// Ежедневное напоминание в выбранное время. Работает локально, без сервера и push-уведомлений.
// iOS не умеет пропускать один день у повторяющегося уведомления, поэтому ставим отдельные
// уведомления на неделю вперёд и обновляем их при каждом открытии приложения и после урока.
final class LocalReminderScheduler: ReminderScheduler {
    private let center = UNUserNotificationCenter.current()
    private static let prefix = "daily-reminder-"
    private static let days = 7

    func schedule(hour: Int, minute: Int, skipToday: Bool) {
        cancel()
        let calendar = Calendar.current
        let now = Date()
        for offset in 0..<Self.days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fire > now else { continue }
            if offset == 0 && skipToday { continue }

            let content = UNMutableNotificationContent()
            content.title = "Миссия дня ждёт"
            content.body = "Пара минут сегодня – и серия занятий не прервётся."
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: Self.prefix + "\(offset)", content: content, trigger: trigger))
        }
    }

    func cancel() {
        let ids = (0..<Self.days).map { Self.prefix + "\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // Запрашивает разрешение на уведомления; true – можно напоминать
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }
}
