import Foundation
import Observation
import WidgetKit

@Observable
class StationStore {

    static let shared = StationStore()

    // MARK: - State

    var watchedStations: [WatchedStation] = [] {
        didSet {
            persist()
            WidgetCenter.shared.reloadAllTimelines()   // push fresh data to widget
        }
    }

    var isRefreshing: Bool = false
    var lastError: String?

    // MARK: - Init

    init() { load() }

    // MARK: - Watchlist Management

    func add(_ station: WatchedStation) {
        guard !watchedStations.contains(where: { $0.id == station.id }) else { return }
        watchedStations.append(station)
    }

    func remove(id: String) {
        watchedStations.removeAll { $0.id == id }
    }

    func isWatching(_ stationID: String) -> Bool {
        watchedStations.contains { $0.id == stationID }
    }

    // MARK: - Live Data Updates

    func updateLevel(id: String, value: Double) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == id }) else { return }
        watchedStations[idx].lastValue   = value
        watchedStations[idx].lastUpdated = Date()
    }

    func setThreshold(id: String, threshold: Double?) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == id }) else { return }
        watchedStations[idx].alarmThreshold = threshold
    }

    func setAlarmEnabled(id: String, enabled: Bool) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == id }) else { return }
        watchedStations[idx].alarmEnabled = enabled
    }

    func setCustomThreshold(id: String, enabled: Bool) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == id }) else { return }
        watchedStations[idx].enableCustomThreshold = enabled
    }

    func setAlarmThresholdNormalLevel(id: String, level: Double?) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == id }) else { return }
        watchedStations[idx].alarmThresholdNormalLevel = level
    }

    func setAlarmThresholdWarningLevel(id: String, level: Double?) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == id }) else { return }
        watchedStations[idx].alarmThresholdWarningLevel = level
    }

    func setAlarmThresholdDangerLevel(id: String, level: Double?) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == id }) else { return }
        watchedStations[idx].alarmThresholdDangerLevel = level
    }
    

    func addCustomAlarm(_ alarm: CustomAlarm, to stationID: String) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == stationID }) else { return }
        watchedStations[idx].customAlarms.append(alarm)
    }

    func updateCustomAlarm(_ alarm: CustomAlarm, in stationID: String) {
        guard let sIdx = watchedStations.firstIndex(where: { $0.id == stationID }),
              let aIdx = watchedStations[sIdx].customAlarms.firstIndex(where: { $0.id == alarm.id })
        else { return }
        watchedStations[sIdx].customAlarms[aIdx] = alarm
    }

    func removeCustomAlarm(id: UUID, from stationID: String) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == stationID }) else { return }
        watchedStations[idx].customAlarms.removeAll { $0.id == id }
    }

    // MARK: - Refresh All

    @MainActor
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        let ids = watchedStations.map { $0.id }
        guard !ids.isEmpty else { return }

        let levels = await PegelOnlineAPI.shared.fetchLevels(for: ids)

        for (id, value) in levels {
            updateLevel(id: id, value: value)

            guard let station = watchedStations.first(where: { $0.id == id }) else { continue }

            // Notifications
            if station.alarmEnabled,
               let threshold = station.alarmThreshold,
               value >= threshold {
                NotificationManager.shared.sendAlarmNotification(for: station, currentValue: value)
                
    
                await LiveActivityManager.shared.update(station: station)
            }
            
            // In refreshAll(), after the existing `if station.alarmEnabled …` block:
            for alarm in station.sortedCustomAlarms where alarm.notificationsEnabled {
                if value >= alarm.threshold {
                    NotificationManager.shared.sendCustomAlarmNotification(
                        for: station, alarm: alarm, currentValue: value
                    )
                }
            }
        
        }
    }

    // MARK: - Persistence — uses App Group so widget can read it

    private let appGroup  = "group.de.felixschick.pegelwatch"
    private let storageKey = "de.felixschick.pegelwatch.watched_stations"

    private func persist() {
        guard let data = try? JSONEncoder().encode(watchedStations) else { return }
        // Write to App Group so the widget extension can read it
        UserDefaults(suiteName: appGroup)?.set(data, forKey: storageKey)
        // Also keep standard for backwards compatibility
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        // Prefer App Group, fall back to standard
        let defaults = UserDefaults(suiteName: appGroup) ?? .standard
        guard
            let data    = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([WatchedStation].self, from: data)
        else { return }
        watchedStations = decoded
    }
}
