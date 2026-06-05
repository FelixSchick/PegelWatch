import Foundation

struct WatchedStation: Identifiable, Codable, Hashable {
    let id: String
    let shortname: String
    let longname: String
    let waterShortname: String
    let waterLongname: String
    let agency: String
    let latitude: Double?
    let longitude: Double?
    let km: Double?

    var alarmThreshold: Double?
    var enableCustomThreshold: Bool = false
    var alarmThresholdNormalLevel: Double?
    var alarmThresholdWarningLevel: Double?
    var alarmThresholdDangerLevel: Double?

    var lastValue: Double?
    var previousValue: Double?
    var lastValueUnit: String = "cm"
    var lastUpdated: Date?

    var alarmEnabled: Bool = true
    var alarmTriggered: Bool = false
    var lastNotifiedAt: Date?

    /// `true` wenn die API für diese Station keine Messdaten bereitstellt (HTTP 404 auf /W/currentmeasurement)
    var noDataAvailable: Bool = false

    var customAlarms: [CustomAlarm] = []
    var customAlarmTriggered: [String: Bool] = [:]
    var customAlarmLastNotifiedAt: [String: Date] = [:]

    var alarmHistory: [AlarmEvent] = []

    // MARK: - Computed

    var waterDisplayName: String {
        waterLongname.isEmpty ? waterShortname : waterLongname.capitalized
    }

    var displayName: String {
        longname.isEmpty ? shortname : longname.capitalized
    }

    var trend: Double? {
        guard let current = lastValue, let previous = previousValue else { return nil }
        return current - previous
    }

    var sortedCustomAlarms: [CustomAlarm] {
        customAlarms.sorted { $0.threshold < $1.threshold }
    }

    var triggeredCustomAlarm: CustomAlarm? {
        guard let value = lastValue else { return nil }
        return sortedCustomAlarms.last { value >= $0.threshold }
    }

    var alarmLevel: AlarmLevel {
        guard let value = lastValue, let threshold = alarmThreshold, threshold > 0 else {
            return .normal
        }

        let ratio = value / threshold

        if enableCustomThreshold {
            if let normal = alarmThresholdNormalLevel, value < normal { return .normal }
            else if ratio < 0.8 { return .normal }

            if let warning = alarmThresholdWarningLevel, value < warning { return .warning }
            else if ratio < 1.0 { return .warning }

            if let danger = alarmThresholdDangerLevel, value < danger { return .danger }
            else if ratio < 1.2 { return .danger }

            return .critical
        } else {
            switch ratio {
            case ..<0.8:        return .normal
            case 0.8..<1.0:     return .warning
            case 1.0..<1.2:     return .danger
            default:            return .critical
            }
        }
    }

    var isStale: Bool {
        guard let updated = lastUpdated else { return true }
        return Date().timeIntervalSince(updated) > 60 * 30
    }

    // MARK: - Init

    init(from station: Station) {
        self.id             = station.uuid
        self.shortname      = station.shortname
        self.longname       = station.longname
        self.waterShortname = station.water.shortname
        self.waterLongname  = station.water.longname
        self.agency         = station.agency
        self.latitude       = station.latitude
        self.longitude      = station.longitude
        self.km             = station.km
    }
}

// MARK: - Preview

extension WatchedStation {
    static let preview: WatchedStation = {
        var s = WatchedStation(from: Station.preview)
        s.lastValue = 182.0
        s.alarmThreshold = 250.0
        s.lastUpdated = Date()
        s.enableCustomThreshold = true
        return s
    }()

    static let previewNoData: WatchedStation = {
        var s = WatchedStation(from: Station.preview)
        s.noDataAvailable = true
        return s
    }()

    static let previewAlarming: WatchedStation = {
        var s = WatchedStation(from: Station.preview)
        s.lastValue = 270.0
        s.alarmThreshold = 250.0
        s.lastUpdated = Date()
        return s
    }()
}
