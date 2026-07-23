import Foundation

/// Die in der App verfügbaren Alarmtöne.
/// Die Dateien liegen als PCM-WAV im App-Bundle (Ordner `Sounds`, < 30 s,
/// wie von UNNotificationSound gefordert).
///
/// Neue Töne hinzufügen: `.wav`-Datei nach `PegelWatch/Sounds/` legen,
/// Namensschema `alarm_<rawValue>.wav`, dann hier einen Enum-Case ergänzen.
enum AlarmSound: String, CaseIterable, Identifiable, Codable {
    // Systemvarianten (keine Bundle-Datei nötig)
    case silent
    case standard
    case standardCritical
    // Gebündelte WAV-Dateien (siehe PegelWatch/Sounds)
    case sirene
    case doppelton
    case puls
    case sonar
    case glocke

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .silent:           return "Kein Ton (nur Banner)"
        case .standard:         return "iOS-Standard"
        case .standardCritical: return "iOS-Standard (kritisch)"
        case .sirene:           return "Sirene"
        case .doppelton:        return "Doppelton"
        case .puls:             return "Puls"
        case .sonar:            return "Sonar"
        case .glocke:           return "Glocke"
        }
    }

    var systemImage: String {
        switch self {
        case .silent:           return "bell.slash"
        case .standard:         return "iphone.radiowaves.left.and.right"
        case .standardCritical: return "exclamationmark.bubble"
        case .sirene:           return "light.beacon.max"
        case .doppelton:        return "waveform"
        case .puls:             return "metronome"
        case .sonar:            return "dot.radiowaves.left.and.right"
        case .glocke:           return "bell"
        }
    }

    /// Dateiname im Bundle, `nil` für Systemtöne oder stumm.
    var fileName: String? {
        switch self {
        case .silent, .standard, .standardCritical: return nil
        case .sirene, .doppelton, .puls, .sonar, .glocke:
            return "alarm_\(rawValue).wav"
        }
    }

    /// `true` wenn dieser Ton keinerlei Audio abspielt.
    var isSilent: Bool { self == .silent }

    /// Nutzt den iOS-Standard-Kritisch-Ton statt einer eigenen Datei.
    var usesSystemCritical: Bool { self == .standardCritical }

    init(idOrDefault id: String?) {
        self = id.flatMap(AlarmSound.init(rawValue:)) ?? .standard
    }
}
