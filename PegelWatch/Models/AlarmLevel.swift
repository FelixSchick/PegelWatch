import SwiftUI

enum AlarmLevel: String, Codable, CaseIterable {
    case normal
    case warning
    case danger
    case critical

    var label: String {
        switch self {
        case .normal:   return "Normal"
        case .warning:  return "Vorwarnung"
        case .danger:   return "Warnstufe"
        case .critical: return "Kritisch"
        }
    }

    var color: Color {
        switch self {
        case .normal:   return .green
        case .warning:  return .yellow
        case .danger:   return .orange
        case .critical: return .red
        }
    }

    var systemImage: String {
        switch self {
        case .normal:   return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .danger:   return "exclamationmark.2"
        case .critical: return "exclamationmark.3"
        }
    }

    var isAlarming: Bool {
        self == .danger || self == .critical
    }
}
