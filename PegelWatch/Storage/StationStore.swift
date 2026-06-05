import Foundation
import Observation
import WidgetKit

@Observable
class StationStore {

    static let shared = StationStore()

    var watchedStations: [WatchedStation] = [] {
        didSet {
            persist()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var isRefreshing: Bool = false
    var lastError: String?
    var lastRefreshed: Date?

    init() {
        load()
        observeICloudChanges()
    }

    // MARK: - Watchlist

    func add(_ station: WatchedStation) {
        guard !watchedStations.contains(where: { $0.id == station.id }) else { return }
        watchedStations.append(station)
        Task {
            await StationStore.shared.refreshAll()
        }
    }

    func remove(id: String) {
        if let station = watchedStations.first(where: { $0.id == id }) {
            Task { await LiveActivityManager.shared.end(for: station) }
        }
        watchedStations.removeAll { $0.id == id }
    }

    func isWatching(_ stationID: String) -> Bool {
        watchedStations.contains { $0.id == stationID }
    }

    // MARK: - Updates

    func updateLevel(id: String, value: Double) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == id }) else { return }
        watchedStations[idx].previousValue = watchedStations[idx].lastValue
        watchedStations[idx].lastValue     = value
        watchedStations[idx].lastUpdated   = Date()
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

    // MARK: - Refresh

    @MainActor
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer {
            isRefreshing = false
            lastRefreshed = Date()
        }

        let ids = watchedStations.map { $0.id }
        guard !ids.isEmpty else { return }

        let (levels, noDataIDs) = await PegelOnlineAPI.shared.fetchLevels(for: ids)

        // Build a single mutated snapshot — avoids triggering didSet (persist + widget reload)
        // for every individual field mutation. The single assignment at the end is the only I/O.
        var updated = watchedStations

        for id in noDataIDs {
            guard let idx = updated.firstIndex(where: { $0.id == id }) else { continue }
            if !updated[idx].noDataAvailable {
                updated[idx].noDataAvailable = true
                print("[PegelWatch] ⚠️ \(id) liefert keine Daten – Station als inaktiv markiert")
            }
        }

        for id in levels.keys {
            guard let idx = updated.firstIndex(where: { $0.id == id }) else { continue }
            if updated[idx].noDataAvailable {
                updated[idx].noDataAvailable = false
            }
        }

        for (id, value) in levels {
            guard let idx = updated.firstIndex(where: { $0.id == id }) else { continue }

            updated[idx].previousValue = updated[idx].lastValue
            updated[idx].lastValue     = value
            updated[idx].lastUpdated   = Date()

            let station = updated[idx]

            // Main threshold alarm
            if station.alarmEnabled, let threshold = station.alarmThreshold {
                let isAbove = value >= threshold

                if isAbove && !station.alarmTriggered {
                    NotificationManager.shared.sendAlarmNotification(for: station, currentValue: value)
                    updated[idx].alarmTriggered  = true
                    updated[idx].lastNotifiedAt  = Date()
                    updated[idx].alarmHistory.append(AlarmEvent(
                        triggeredAt: Date(), alarmLevel: station.alarmLevel,
                        level: value, threshold: threshold, label: "Alarm", kind: .triggered
                    ))
                } else if !isAbove && station.alarmTriggered {
                    updated[idx].alarmTriggered = false
                    updated[idx].alarmHistory.append(AlarmEvent(
                        triggeredAt: Date(), level: value, threshold: threshold,
                        label: "Entwarnung", kind: .recovered
                    ))
                }
            }

            // Custom alarms
            for alarm in station.sortedCustomAlarms where alarm.notificationsEnabled {
                let key      = alarm.id.uuidString
                let isAbove  = value >= alarm.threshold
                let wasAbove = station.customAlarmTriggered[key] ?? false

                if isAbove && !wasAbove {
                    NotificationManager.shared.sendCustomAlarmNotification(
                        for: station, alarm: alarm, currentValue: value
                    )
                    updated[idx].customAlarmTriggered[key]      = true
                    updated[idx].customAlarmLastNotifiedAt[key] = Date()
                    updated[idx].alarmHistory.append(AlarmEvent(
                        triggeredAt: Date(), level: value, threshold: alarm.threshold,
                        label: alarm.name, kind: .triggered
                    ))
                } else if !isAbove && wasAbove {
                    updated[idx].customAlarmTriggered[key] = false
                    updated[idx].alarmHistory.append(AlarmEvent(
                        triggeredAt: Date(), level: value, threshold: alarm.threshold,
                        label: alarm.name, kind: .recovered
                    ))
                }
            }
        }

        // Single assignment — triggers persist + widget reload exactly once
        watchedStations = updated

        // Update live activities after the state is committed
        for station in watchedStations {
            await LiveActivityManager.shared.update(station: station)
        }
    }

    // MARK: - Persistence
    // Primary: iCloud KV (syncs across devices), mirror: App Group (widget reads here)

    private let appGroup   = "group.de.felixschick.pegelwatch"
    private let storageKey = "de.felixschick.pegelwatch.watched_stations"

    private func persist() {
        guard let data = try? JSONEncoder().encode(watchedStations) else { return }
        NSUbiquitousKeyValueStore.default.set(data, forKey: storageKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        UserDefaults(suiteName: appGroup)?.set(data, forKey: storageKey)
    }

    private func load() {
        if let data    = NSUbiquitousKeyValueStore.default.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([WatchedStation].self, from: data) {
            watchedStations = decoded
            UserDefaults(suiteName: appGroup)?.set(data, forKey: storageKey)
            return
        }
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
