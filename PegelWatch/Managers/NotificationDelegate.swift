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
                StationStore.shared.muteAlarms(for: stationID, duration: AlarmMuteDuration.oneHour.seconds)
            }
        case NotificationManager.muteOneDayAction:
            await MainActor.run {
                StationStore.shared.muteAlarms(for: stationID, duration: AlarmMuteDuration.oneDay.seconds)
            }
        case UNNotificationDefaultActionIdentifier:
            // Tap auf die Mitteilung → Detailansicht der Station öffnen
            await MainActor.run {
                AppRouter.shared.selectedTab = .watchlist
                AppRouter.shared.pendingStationID = stationID
            }
        default:
            break
        }
    }
}
