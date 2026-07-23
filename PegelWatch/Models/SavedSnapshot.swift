import SwiftUI

struct SavedSnapshot: Identifiable, Codable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var title: String
    var timeframeDays: Int
    var stations: [SnapshotStationData]
}

extension SavedSnapshot: Hashable {
    static func == (lhs: SavedSnapshot, rhs: SavedSnapshot) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: -

struct SnapshotStationData: Identifiable, Codable {
    var id: String
    var shortname: String
    var longname: String
    var waterShortname: String
    var waterLongname: String
    var agency: String
    var lastValue: Double?
    var previousValue: Double?
    var noDataAvailable: Bool
    var alarmLevel: AlarmLevel
    var lastUpdated: Date?
    var alarmThreshold: Double?
    var alarmThresholdNormalLevel: Double?
    var alarmThresholdWarningLevel: Double?
    var alarmThresholdDangerLevel: Double?
    var customAlarms: [CustomAlarm]
    var history: [HistoryPoint]

    struct HistoryPoint: Codable {
        var timestamp: Date
        var value: Double
    }

    var displayName: String { (longname.isEmpty ? shortname : longname.capitalized).replacingStauAbbreviations }
    var waterDisplayName: String { waterLongname.isEmpty ? waterShortname : waterLongname.capitalized }

    var trend: Double? {
        guard let current = lastValue, let previous = previousValue else { return nil }
        return current - previous
    }

    // Print-safe color: amber instead of system yellow, which is illegible on white
    var snapshotColor: Color {
        guard !noDataAvailable else { return .gray }
        switch alarmLevel {
        case .normal:   return Color(red: 0.13, green: 0.69, blue: 0.30)
        case .warning:  return Color(red: 0.80, green: 0.55, blue: 0.00)
        case .danger:   return Color(red: 0.90, green: 0.35, blue: 0.00)
        case .critical: return Color(red: 0.85, green: 0.10, blue: 0.10)
        }
    }

    init(from station: WatchedStation, history: [HistoryPoint]) {
        id = station.id
        shortname = station.shortname
        longname = station.longname
        waterShortname = station.waterShortname
        waterLongname = station.waterLongname
        agency = station.agency
        lastValue = station.lastValue
        previousValue = station.previousValue
        noDataAvailable = station.noDataAvailable
        alarmLevel = station.alarmLevel
        lastUpdated = station.lastUpdated
        alarmThreshold = station.alarmThreshold
        alarmThresholdNormalLevel = station.alarmThresholdNormalLevel
        alarmThresholdWarningLevel = station.alarmThresholdWarningLevel
        alarmThresholdDangerLevel = station.alarmThresholdDangerLevel
        customAlarms = station.customAlarms
        self.history = history
    }
}
