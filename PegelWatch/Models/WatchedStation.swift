import Foundation

/// A station the user has chosen to monitor.
/// This is stored locally and enriched with live data.
struct WatchedStation: Identifiable, Codable, Hashable {
    let id: String            // = station.uuid
    let shortname: String
    let longname: String
    let waterShortname: String
    let waterLongname: String
    let agency: String
    let latitude: Double?
    let longitude: Double?
    let km: Double?

    /// User-defined alarm threshold in cm
    var alarmThreshold: Double?
    /// User-defined alarm threshold in cm
    var enableCustomThreshold: Bool = false
    var alarmThresholdNormalLevel: Double?
    var alarmThresholdWarningLevel: Double?
    var alarmThresholdDangerLevel: Double?

    /// Live data — updated from API
    var lastValue: Double?
    var lastValueUnit: String = "cm"
    var lastUpdated: Date?

    /// Whether the user has enabled alarm notifications for this station
    var alarmEnabled: Bool = true

    // MARK: - Computed

    var waterDisplayName: String {
        waterLongname.isEmpty ? waterShortname : waterLongname.capitalized
    }

    var displayName: String {
        longname.isEmpty ? shortname : longname.capitalized
    }
    
    // In WatchedStation.swift — add one new property:
    var customAlarms: [CustomAlarm] = []

    // Computed: all alarms sorted by threshold (used by chart and notifications)
    var sortedCustomAlarms: [CustomAlarm] {
        customAlarms.sorted { $0.threshold < $1.threshold }
    }

    // Computed: the highest custom alarm that has been crossed
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
            
            if alarmThresholdNormalLevel != nil {
                if value < alarmThresholdNormalLevel! { return .normal }
            } else if ratio<0.8 { return .normal }
            
            if alarmThresholdWarningLevel != nil {
                if value < alarmThresholdWarningLevel! { return .warning }
            } else if ratio<1.0 { return .warning }
            
            if alarmThresholdDangerLevel != nil {
                if value < alarmThresholdDangerLevel! { return .danger }
            } else if ratio<1.2 { return .danger }
            
            return .critical
        } else {
            
            switch ratio {
                case ..<0.8:  return .normal
                case 0.8..<1.0: return .warning
            case 1.0..<1.2: return .danger
                default:      return .critical
            }
        }
    }

    var isStale: Bool {
        guard let updated = lastUpdated else { return true }
        return Date().timeIntervalSince(updated) > 60 * 30 // 30 min
    }

    // MARK: - Init from Station

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

    static let previewAlarming: WatchedStation = {
        var s = WatchedStation(from: Station.preview)
        s.lastValue = 270.0
        s.alarmThreshold = 250.0
        s.lastUpdated = Date()
        return s
    }()
}
