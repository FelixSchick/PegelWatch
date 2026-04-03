import UserNotifications
import Foundation

class NotificationManager {

    static let shared = NotificationManager()

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

    // MARK: - Send

    func sendAlarmNotification(for station: WatchedStation, currentValue: Double) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Pegel-Alarm: \(station.shortname)"
        content.body = buildBody(station: station, value: currentValue)
        content.sound = .defaultCritical
        content.interruptionLevel = .critical
        content.badge = 1

        schedule(id: "alarm_\(station.id)", content: content, delay: 1)
    }

    func sendCustomAlarmNotification(for station: WatchedStation, alarm: CustomAlarm, currentValue: Double) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ \(alarm.name)"
        content.body  = "\(station.displayName) (\(station.waterDisplayName)): " +
                        "\(Int(currentValue)) cm – Schwelle \(Int(alarm.threshold)) cm überschritten."
        content.sound = .default

        schedule(id: "custom-\(station.id)-\(alarm.id.uuidString)", content: content)
    }

    func sendTestAlarmNotification() {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Test"
        content.body = "Test"
        content.sound = .defaultCritical
        content.interruptionLevel = .critical
        content.badge = 1

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["test"])
        schedule(id: "test", content: content, delay: 5)
    }

    func cancelAlarm(for stationID: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["alarm_\(stationID)"])
    }

    func cancelAllAlarms() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Private

    private func schedule(id: String, content: UNMutableNotificationContent, delay: TimeInterval? = nil) {
        let trigger = delay.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Notification error: \(error)") }
        }
    }

    private func buildBody(station: WatchedStation, value: Double) -> String {
        var parts = ["\(station.waterDisplayName) bei \(station.displayName)", "Aktuell: \(Int(value)) cm"]
        if let threshold = station.alarmThreshold {
            parts.append("(Schwelle: \(Int(threshold)) cm)")
        }
        return parts.joined(separator: " · ")
    }
}
