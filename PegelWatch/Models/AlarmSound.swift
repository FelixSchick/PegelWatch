import Foundation

/// Die in der App verfügbaren Alarmtöne.
/// Die Dateien liegen als PCM-WAV im App-Bundle (Ordner `Sounds`, < 30 s,
/// wie von UNNotificationSound gefordert).
enum AlarmSound: String, CaseIterable, Identifiable, Codable {
    case standard
    case sirene
    case doppelton
    case puls
    case sonar
    case glocke

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:  return "Standard (iOS)"
        case .sirene:    return "Sirene"
        case .doppelton: return "Doppelton"
        case .puls:      return "Puls"
        case .sonar:     return "Sonar"
        case .glocke:    return "Glocke"
        }
    }

    var systemImage: String {
        switch self {
        case .standard:  return "iphone.radiowaves.left.and.right"
        case .sirene:    return "light.beacon.max"
        case .doppelton: return "waveform"
        case .puls:      return "metronome"
        case .sonar:     return "dot.radiowaves.left.and.right"
        case .glocke:    return "bell"
        }
    }

    /// Dateiname im Bundle, `nil` für den iOS-Standardton.
    var fileName: String? {
        self == .standard ? nil : "alarm_\(rawValue).wav"
    }

    init(idOrDefault id: String?) {
        self = id.flatMap(AlarmSound.init(rawValue:)) ?? .standard
    }
}
