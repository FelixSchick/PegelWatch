import UserNotifications

/// Verarbeitet Mitteilungs-Aktionen (Stummschalten direkt aus der Benachrichtigung)
/// und sorgt dafür, dass Alarme auch bei geöffneter App als Banner erscheinen.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationDelegate()

    // Banner + Ton auch anzeigen, wenn die App im Vordergrund ist.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let stationID = response.notification.request.content
            .userInfo[NotificationManager.stationIDKey] as? String else { return }

        switch response.actionIdentifier {
        case NotificationManager.muteOneHourAction:
            await MainActor.run {
                StationStore.shared.muteAlarms(for: stationID, duration: 60 * 60)
            }
        case NotificationManager.muteOneDayAction:
            await MainActor.run {
                StationStore.shared.muteAlarms(for: stationID, duration: 24 * 60 * 60)
            }
        default:
            break
        }
    }
}
