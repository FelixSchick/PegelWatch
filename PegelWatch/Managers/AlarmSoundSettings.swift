import Foundation
import Observation

/// Globale Ton-Einstellungen für Alarm-Benachrichtigungen.
/// Wird in UserDefaults gespeichert; eigene Alarme können den Ton
/// pro Alarm überschreiben (`CustomAlarm.soundID`).
@Observable
final class AlarmSoundSettings {

    static let shared = AlarmSoundSettings()

    private static let soundKey          = "alarm.sound"
    private static let volumeKey         = "alarm.criticalVolume"
    private static let criticalAlertsKey = "alarm.useCriticalAlerts"

    /// Standardton für alle Pegel-Alarme.
    var alarmSound: AlarmSound {
        didSet { UserDefaults.standard.set(alarmSound.rawValue, forKey: Self.soundKey) }
    }

    /// Lautstärke (0.0–1.0) für kritische Warnungen. iOS wendet sie nur an,
    /// wenn die Mitteilung als Critical Alert zugestellt wird.
    var criticalVolume: Double {
        didSet { UserDefaults.standard.set(criticalVolume, forKey: Self.volumeKey) }
    }

    /// Hauptalarme als kritische Warnung senden (durchbricht Stummmodus & Fokus,
    /// benötigt das Critical-Alerts-Entitlement von Apple).
    var useCriticalAlerts: Bool {
        didSet { UserDefaults.standard.set(useCriticalAlerts, forKey: Self.criticalAlertsKey) }
    }

    private init() {
        let defaults = UserDefaults.standard
        alarmSound = AlarmSound(idOrDefault: defaults.string(forKey: Self.soundKey))
        let storedVolume = defaults.object(forKey: Self.volumeKey) as? Double
        criticalVolume = storedVolume ?? 1.0
        let storedCritical = defaults.object(forKey: Self.criticalAlertsKey) as? Bool
        useCriticalAlerts = storedCritical ?? true
    }
}
