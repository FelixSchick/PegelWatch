import UserNotifications
import Foundation

class NotificationManager {

    static let shared = NotificationManager()

    // Kategorie & Aktionen für Pegel-Alarme
    static let alarmCategory      = "PEGEL_ALARM"
    static let muteOneHourAction  = "MUTE_1H"
    static let muteOneDayAction   = "MUTE_24H"
    static let stationIDKey       = "stationID"

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

    /// Registriert die Alarm-Kategorie mit Schnellaktionen
    /// ("1 Std. / 24 Std. stumm" direkt aus der Mitteilung).
    func registerCategories() {
        let muteHour = UNNotificationAction(
            identifier: Self.muteOneHourAction,
            title: "1 Stunde stumm",
            options: []
        )
        let muteDay = UNNotificationAction(
            identifier: Self.muteOneDayAction,
            title: "24 Stunden stumm",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.alarmCategory,
            actions: [muteHour, muteDay],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Send

    func sendAlarmNotification(for station: WatchedStation, currentValue: Double) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Pegel-Alarm: \(station.shortname.replacingStauAbbreviations)"
        content.body = buildBody(station: station, value: currentValue)
        content.badge = 1
        content.categoryIdentifier = Self.alarmCategory
        content.userInfo = [Self.stationIDKey: station.id]

        let settings = AlarmSoundSettings.shared
        if settings.useCriticalAlerts {
            content.sound = alarmSound(settings.alarmSound, critical: true)
            content.interruptionLevel = .critical
        } else {
            content.sound = alarmSound(settings.alarmSound, critical: false)
            content.interruptionLevel = .timeSensitive
        }

        schedule(id: "alarm_\(station.id)", content: content, delay: 1)
    }

    func sendCustomAlarmNotification(for station: WatchedStation, alarm: CustomAlarm, currentValue: Double) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ \(alarm.name)"
        content.body  = "\(station.displayName) (\(station.waterDisplayName)): " +
                        "\(Int(currentValue)) cm – Schwelle \(Int(alarm.threshold)) cm überschritten."
        content.categoryIdentifier = Self.alarmCategory
        content.userInfo = [Self.stationIDKey: station.id]
        content.interruptionLevel = .timeSensitive

        // Ton des Alarms, sonst der global eingestellte Ton
        let sound = alarm.soundID.map { AlarmSound(idOrDefault: $0) }
            ?? AlarmSoundSettings.shared.alarmSound
        content.sound = alarmSound(sound, critical: false)

        schedule(id: "custom-\(station.id)-\(alarm.id.uuidString)", content: content)
    }

    /// Testmitteilung mit den aktuell gewählten Ton-Einstellungen.
    func sendTestAlarmNotification() {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Test-Alarm"
        content.body = "So klingt und erscheint ein Pegel-Alarm."
        content.badge = 1

        let settings = AlarmSoundSettings.shared
        if settings.useCriticalAlerts {
            content.sound = alarmSound(settings.alarmSound, critical: true)
            content.interruptionLevel = .critical
        } else {
            content.sound = alarmSound(settings.alarmSound, critical: false)
            content.interruptionLevel = .timeSensitive
        }

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

    /// Baut den UNNotificationSound aus Ton-Auswahl, Lautstärke und Kritikalität.
    /// Die Lautstärke greift nur bei kritischen Warnungen – normale Mitteilungen
    /// folgen immer der Systemlautstärke.
    private func alarmSound(_ sound: AlarmSound, critical: Bool) -> UNNotificationSound {
        let volume = Float(AlarmSoundSettings.shared.criticalVolume)
        if critical {
            if let file = sound.fileName {
                return .criticalSoundNamed(UNNotificationSoundName(file), withAudioVolume: volume)
            }
            return .defaultCriticalSound(withAudioVolume: volume)
        }
        if let file = sound.fileName {
            return UNNotificationSound(named: UNNotificationSoundName(file))
        }
        return .default
    }

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
