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
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var isRefreshing: Bool = false
    var lastError: String?

    // MARK: - Init

    init() {
        load()
        observeICloudChanges()
    }

    // MARK: - Watchlist Management

    func add(_ station: WatchedStation) {
        guard !watchedStations.contains(where: { $0.id == station.id }) else { return }
        watchedStations.append(station)
        
        //refresh
        Task.init {
            await StationStore.shared.refreshAll()
        }
    }

    func remove(id: String) {
        watchedStations.removeAll { $0.id == id }
        
        //refresh
        Task.init {
            await StationStore.shared.refreshAll()
        }
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

    func clearAlarmHistory(for stationID: String) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == stationID }) else { return }
        watchedStations[idx].alarmHistory.removeAll()
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
            guard let idx = watchedStations.firstIndex(where: { $0.id == id }) else { continue }
            let station = watchedStations[idx]

            
            
            // ── Main threshold alarm ─────────────────────────────────────────
            if station.alarmEnabled, let threshold = station.alarmThreshold {

                let isAbove = value >= threshold
            
                await LiveActivityManager.shared.update(station: watchedStations[idx])
                if isAbove && !station.alarmTriggered {
                    // First crossing upward: fire once
                    NotificationManager.shared.sendAlarmNotification(for: station, currentValue: value)
                    watchedStations[idx].alarmTriggered = true
                    watchedStations[idx].lastNotifiedAt = Date()
                    watchedStations[idx].alarmHistory.append(AlarmEvent(
                        triggeredAt: Date(), alarmLevel: station.alarmLevel, level: value, threshold: threshold,
                        label: "Alarm", kind: .triggered
                    ))
                    

                } else if !isAbove && station.alarmTriggered {
                    // Recovered: reset flag + record
                    watchedStations[idx].alarmTriggered = false
                    watchedStations[idx].alarmHistory.append(AlarmEvent(
                        triggeredAt: Date(), level: value, threshold: threshold,
                        label: "Entwarnung", kind: .recovered
                    ))
                    
                    await LiveActivityManager.shared.update(station: watchedStations[idx])
                }
            }

            // ── Custom alarms ────────────────────────────────────────────────
            for alarm in station.sortedCustomAlarms where alarm.notificationsEnabled {
                print("Test 2")
                let key     = alarm.id.uuidString
                let isAbove = value >= alarm.threshold
                let wasAbove = station.customAlarmTriggered[key] ?? false

                if isAbove && !wasAbove {
                    NotificationManager.shared.sendCustomAlarmNotification(
                        for: station, alarm: alarm, currentValue: value
                    )
                    watchedStations[idx].customAlarmTriggered[key]      = true
                    watchedStations[idx].customAlarmLastNotifiedAt[key] = Date()
                    watchedStations[idx].alarmHistory.append(AlarmEvent(
                        triggeredAt: Date(), level: value, threshold: alarm.threshold,
                        label: alarm.name, kind: .triggered
                    ))
                } else if !isAbove && wasAbove {
                    watchedStations[idx].customAlarmTriggered[key] = false
                    watchedStations[idx].alarmHistory.append(AlarmEvent(
                        triggeredAt: Date(), level: value, threshold: alarm.threshold,
                        label: alarm.name, kind: .recovered
                    ))
                }
            }
        }
    }

    // MARK: - Persistence
    // Primary: iCloud KV (syncs across devices)
    // Mirror:  App Group UserDefaults (widget extension reads from here)

    private let appGroup   = "group.de.felixschick.pegelwatch"
    private let storageKey = "de.felixschick.pegelwatch.watched_stations"

    private func persist() {
        guard let data = try? JSONEncoder().encode(watchedStations) else { return }
        NSUbiquitousKeyValueStore.default.set(data, forKey: storageKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        UserDefaults(suiteName: appGroup)?.set(data, forKey: storageKey)
    }

    private func load() {
        // Prefer iCloud KV (most up-to-date across devices)
        if let data    = NSUbiquitousKeyValueStore.default.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([WatchedStation].self, from: data) {
            watchedStations = decoded
            UserDefaults(suiteName: appGroup)?.set(data, forKey: storageKey)
            return
        }
        // Fall back to App Group
        if let data    = UserDefaults(suiteName: appGroup)?.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([WatchedStation].self, from: data) {
            watchedStations = decoded
        }
    }

    private func observeICloudChanges() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let keys = (notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
            guard keys.contains(self.storageKey) else { return }
            if let data    = NSUbiquitousKeyValueStore.default.data(forKey: self.storageKey),
               let decoded = try? JSONDecoder().decode([WatchedStation].self, from: data) {
                self.watchedStations = decoded
                UserDefaults(suiteName: self.appGroup)?.set(data, forKey: self.storageKey)
            }
        }
    }
}
