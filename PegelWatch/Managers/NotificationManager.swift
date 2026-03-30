import UserNotifications
import Foundation

class NotificationManager {

    static let shared = NotificationManager()

    // MARK: - Permission

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            print("Notification permission granted: \(granted)")
        } catch {
            print("Notification permission error: \(error)")
        }
    }

    var hasPermission: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    // MARK: - Send Alarm

    func sendAlarmNotification(for station: WatchedStation, currentValue: Double) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Pegel-Alarm: \(station.shortname)"
        content.body = buildBody(station: station, value: currentValue)
        content.sound = .defaultCritical
        content.interruptionLevel = .critical
        content.badge = 1

        let request = UNNotificationRequest(
            identifier: "alarm_\(station.id)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        print("Alarm sent")
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Notification error: \(error)") }
        }
    }
    
    func sendCustomAlarmNotification(for station: WatchedStation,
                                      alarm: CustomAlarm,
                                      currentValue: Double) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ \(alarm.name)"
        content.body  = "\(station.displayName) (\(station.waterDisplayName)): " +
                        "\(Int(currentValue)) cm – Schwelle \(Int(alarm.threshold)) cm überschritten."
        content.sound = .default

        let id = "custom-\(station.id)-\(alarm.id.uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func sendTestAlarmNotification() {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Test"
        content.body = "Test"
        content.sound = .defaultCritical
        content.interruptionLevel = .critical
        content.badge = 1
        
        let notificationCenter = UNUserNotificationCenter.current()
        
        let request = UNNotificationRequest(
            identifier: "test",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["test"])
        notificationCenter.add(request)
    }

    func cancelAlarm(for stationID: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["alarm_\(stationID)"])
    }

    func cancelAllAlarms() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Private

    private func buildBody(station: WatchedStation, value: Double) -> String {
        var parts: [String] = []
        parts.append("\(station.waterDisplayName) bei \(station.displayName)")
        parts.append("Aktuell: \(Int(value)) cm")
        if let threshold = station.alarmThreshold {
            parts.append("(Schwelle: \(Int(threshold)) cm)")
        }
        return parts.joined(separator: " · ")
    }
}
