import UserNotifications
import Foundation

/// Gemeinsame Quelle für Stummschalt-Dauern und ihre Labels —
/// genutzt von Mitteilungs-Aktionen und dem Menü in der Detailansicht.
enum AlarmMuteDuration: CaseIterable {
    case thirtyMinutes, oneHour, sixHours, oneDay

    var seconds: TimeInterval {
        switch self {
        case .thirtyMinutes: return 30 * 60
        case .oneHour:       return 60 * 60
        case .sixHours:      return 6 * 60 * 60
        case .oneDay:        return 24 * 60 * 60
        }
    }

    var label: String {
        switch self {
        case .thirtyMinutes: return "30 Minuten"
        case .oneHour:       return "1 Stunde"
        case .sixHours:      return "6 Stunden"
        case .oneDay:        return "24 Stunden"
        }
    }
}

class NotificationManager {

    static let shared = NotificationManager()

    // Kategorie & Aktionen für Pegel-Alarme
    static let alarmCategory          = "PEGEL_ALARM"
    static let muteHalfHourAction     = "MUTE_30M"
    static let muteOneHourAction      = "MUTE_1H"
    static let muteOneDayAction       = "MUTE_24H"
    static let stationIDKey           = "stationID"

    func requestPermission() async {
        do {
            // .criticalAlert ist ohne das Apple-Entitlement wirkungslos (wird
            // schlicht nicht gewährt), aber sobald das Entitlement da ist,
            // greifen Lautstärkeregler & Stummmodus-Durchbruch automatisch.
            let _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
        } catch {
            #if DEBUG
            print("Notification permission error: \(error)")
            #endif
        }
    }

    var hasPermission: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    /// Registriert die Alarm-Kategorie mit Schnellaktionen
    /// (30 Min / 1 Std. / 24 Std. stumm, direkt aus der Mitteilung).
    func registerCategories() {
        let muteHalfHour = UNNotificationAction(
            identifier: Self.muteHalfHourAction,
            title: "\(AlarmMuteDuration.thirtyMinutes.label) stumm",
            options: []
        )
        let muteHour = UNNotificationAction(
            identifier: Self.muteOneHourAction,
            title: "\(AlarmMuteDuration.oneHour.label) stumm",
            options: []
        )
        let muteDay = UNNotificationAction(
            identifier: Self.muteOneDayAction,
            title: "\(AlarmMuteDuration.oneDay.label) stumm",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.alarmCategory,
            actions: [muteHalfHour, muteHour, muteDay],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Send

    func sendAlarmNotification(for station: WatchedStation, currentValue: Double) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Pegel-Alarm: \(station.displayShortname)"
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
        var customBody = "\(station.displayName) (\(station.waterDisplayName)): " +
                         "\(Int(currentValue)) cm – Schwelle \(Int(alarm.threshold)) cm überschritten."
        if let rate = station.riseRateCmPerHour, abs(rate) >= 2 {
            customBody += rate > 0 ? String(format: " · ↑ %+.0f cm/h", rate) : String(format: " · ↓ %.0f cm/h", rate)
        }
        content.body = customBody
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
    /// folgen immer der Systemlautstärke. Für `.silent` gibt es `nil` (nur Banner).
    private func alarmSound(_ sound: AlarmSound, critical: Bool) -> UNNotificationSound? {
        if sound.isSilent { return nil }
        let volume = Float(AlarmSoundSettings.shared.criticalVolume)
        // `.standardCritical` ist immer der iOS-Standard-Kritisch-Ton –
        // unabhängig davon, ob die Mitteilung selbst kritisch zugestellt wird.
        if sound.usesSystemCritical {
            return .defaultCriticalSound(withAudioVolume: volume)
        }
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
        if let rate = station.riseRateCmPerHour, abs(rate) >= 2 {
            parts.append(rate > 0 ? String(format: "↑ %+.0f cm/h", rate) : String(format: "↓ %.0f cm/h", rate))
        }
        return parts.joined(separator: " · ")
    }
}
