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

    var groups: [StationGroup] = [] {
        didSet { persistGroups() }
    }

    var isRefreshing: Bool = false
    var lastError: String?
    var lastRefreshed: Date?

    init() {
        load()
        loadGroups()
        observeICloudChanges()
        SpotlightIndexer.reindex(watchedStations)
    }

    // MARK: - Watchlist

    func add(_ station: WatchedStation) {
        guard !watchedStations.contains(where: { $0.id == station.id }) else { return }
        watchedStations.append(station)
        SpotlightIndexer.index(station)
        Task {
            // Erste Station = erster Moment, in dem Alarme Sinn ergeben
            await NotificationManager.shared.requestPermissionIfNeeded()
            await StationStore.shared.refreshAll()
        }
    }

    /// Entfernt eine Station und registriert das Wiederherstellen (Schütteln
    /// zum Widerrufen) inklusive Position, Schwellen, Alarmen und Gruppen.
    func remove(id: String, undoManager: UndoManager?) {
        guard let index = watchedStations.firstIndex(where: { $0.id == id }) else { return }
        let station = watchedStations[index]
        let groupIDs = groups.filter { $0.stationIDs.contains(id) }.map(\.id)
        remove(id: id)
        undoManager?.registerUndo(withTarget: self) { store in
            store.restore(station, at: index, groupIDs: groupIDs)
        }
        undoManager?.setActionName("Station entfernen")
    }

    func remove(id: String) {
        if let station = watchedStations.first(where: { $0.id == id }) {
            Task { await LiveActivityManager.shared.end(for: station) }
        }
        watchedStations.removeAll { $0.id == id }
        SpotlightIndexer.remove(id: id)
        // Clean up group membership
        for idx in groups.indices {
            groups[idx].stationIDs.removeAll { $0 == id }
        }
    }

    private func restore(_ station: WatchedStation, at index: Int, groupIDs: [UUID]) {
        guard !watchedStations.contains(where: { $0.id == station.id }) else { return }
        watchedStations.insert(station, at: min(index, watchedStations.count))
        for idx in groups.indices where groupIDs.contains(groups[idx].id) {
            groups[idx].stationIDs.append(station.id)
        }
        SpotlightIndexer.index(station)
        Task { await refreshAll() }
    }

    func isWatching(_ stationID: String) -> Bool {
        watchedStations.contains { $0.id == stationID }
    }

    // MARK: - Reordering

    enum GroupTarget {
        case unchanged
        case group(UUID?)
    }

    /// Reordnet die angegebenen Stationen so, dass sie direkt vor `targetID` stehen
    /// (oder ans Ende, wenn `targetID` nil ist). Optional wird dabei auch die
    /// Gruppenzugehörigkeit gesetzt — `.group(nil)` entfernt sie aus allen Gruppen,
    /// `.group(id)` fügt sie der betreffenden Gruppe hinzu.
    func moveWatchedStations(_ ids: [String], before targetID: String?, toGroup target: GroupTarget = .unchanged) {
        guard !ids.isEmpty else { return }
        let movingSet = Set(ids)

        var updated = watchedStations
        var moved: [WatchedStation] = []
        updated.removeAll { station in
            guard movingSet.contains(station.id) else { return false }
            moved.append(station)
            return true
        }
        if let targetID, let idx = updated.firstIndex(where: { $0.id == targetID }) {
            updated.insert(contentsOf: moved, at: idx)
        } else {
            updated.append(contentsOf: moved)
        }
        watchedStations = updated

        if case .group(let groupID) = target {
            for idx in groups.indices {
                groups[idx].stationIDs.removeAll { movingSet.contains($0) }
            }
            if let groupID, let gIdx = groups.firstIndex(where: { $0.id == groupID }) {
                groups[gIdx].stationIDs.append(contentsOf: ids.filter { !groups[gIdx].stationIDs.contains($0) })
            }
        }
    }

    // MARK: - Groups

    func addGroup(_ group: StationGroup) {
        groups.append(group)
    }

    func removeGroup(id: UUID) {
        groups.removeAll { $0.id == id }
    }

    func updateGroup(_ group: StationGroup) {
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[idx] = group
    }

    // MARK: - Updates

    func updateLevel(id: String, value: Double) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == id }) else { return }
        watchedStations[idx].previousUpdated = watchedStations[idx].lastUpdated
        watchedStations[idx].previousValue   = watchedStations[idx].lastValue
        watchedStations[idx].lastValue       = value
        watchedStations[idx].lastUpdated     = Date()
    }

    func setThreshold(id: String, threshold: Double?) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == id }) else { return }
        watchedStations[idx].alarmThreshold = threshold
        if threshold != nil {
            Task { await NotificationManager.shared.requestPermissionIfNeeded() }
        }
    }

    func setAlarmEnabled(id: String, enabled: Bool) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == id }) else { return }
        watchedStations[idx].alarmEnabled = enabled
    }

    /// Unterdrückt Alarm-Mitteilungen der Station für die angegebene Dauer.
    func muteAlarms(for stationID: String, duration: TimeInterval) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == stationID }) else { return }
        watchedStations[idx].alarmMutedUntil = Date().addingTimeInterval(duration)
    }

    func unmuteAlarms(for stationID: String) {
        guard let idx = watchedStations.firstIndex(where: { $0.id == stationID }) else { return }
        watchedStations[idx].alarmMutedUntil = nil
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
        Task { await NotificationManager.shared.requestPermissionIfNeeded() }
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
        // lastError bleibt während des Ladens stehen, damit der Hinweis nicht flackert.
        defer { isRefreshing = false }

        let ids = watchedStations.map { $0.id }
        guard !ids.isEmpty else {
            lastError = nil
            return
        }

        let pegelIDs = ids.filter { !HeichwaasserAPI.isLuxembourgStation($0) }
        let luxIDs = ids.filter { HeichwaasserAPI.isLuxembourgStation($0) }

        async let pegelResult = PegelOnlineAPI.shared.fetchLevels(for: pegelIDs)
        async let luxResult = HeichwaasserAPI.shared.fetchLevels(for: luxIDs)

        let (pegelData, luxData) = await (pegelResult, luxResult)

        var levels = pegelData.levels
        var noDataIDs = pegelData.noDataIDs
        for (id, value) in luxData.levels { levels[id] = value }
        for id in luxData.noDataIDs { noDataIDs.insert(id) }

        // Stationen ohne Wert und ohne „keine Daten“-Antwort sind am Netzwerk
        // gescheitert. Nur echte Antworten zählen als Aktualisierung — sonst
        // zeigte die Liste „Aktualisiert gerade eben“, obwohl nichts geladen wurde.
        let failedIDs = Set(ids).subtracting(levels.keys).subtracting(noDataIDs)
        if failedIDs.count == ids.count {
            lastError = "Keine Verbindung zu den Pegeldiensten. Angezeigt werden die zuletzt geladenen Werte."
            return
        }
        lastError = failedIDs.isEmpty
            ? nil
            : "\(failedIDs.count) von \(ids.count) Stationen konnten nicht aktualisiert werden."
        lastRefreshed = Date()

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

            updated[idx].previousUpdated = updated[idx].lastUpdated
            updated[idx].previousValue   = updated[idx].lastValue
            updated[idx].lastValue       = value
            updated[idx].lastUpdated     = Date()

            let station = updated[idx]

            // Solange stummgeschaltet, wird die Alarm-Auswertung komplett pausiert:
            // Der Trigger-Latch darf nicht gesetzt werden, sonst bliebe eine
            // Überschreitung nach Ablauf der Stummschaltung dauerhaft unbemerkt.
            guard !station.isAlarmMuted else { continue }

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

    private let appGroup    = "group.de.felixschick.pegelwatch"
    private let storageKey  = "de.felixschick.pegelwatch.watched_stations"
    private let groupsKey   = "de.felixschick.pegelwatch.groups"

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

    private func persistGroups() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        NSUbiquitousKeyValueStore.default.set(data, forKey: groupsKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        UserDefaults(suiteName: appGroup)?.set(data, forKey: groupsKey)
    }

    private func loadGroups() {
        if let data    = NSUbiquitousKeyValueStore.default.data(forKey: groupsKey),
           let decoded = try? JSONDecoder().decode([StationGroup].self, from: data) {
            groups = decoded
            return
        }
        if let data    = UserDefaults(suiteName: appGroup)?.data(forKey: groupsKey),
           let decoded = try? JSONDecoder().decode([StationGroup].self, from: data) {
            groups = decoded
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
            if keys.contains(self.storageKey),
               let data    = NSUbiquitousKeyValueStore.default.data(forKey: self.storageKey),
               let decoded = try? JSONDecoder().decode([WatchedStation].self, from: data) {
                self.watchedStations = decoded
                UserDefaults(suiteName: self.appGroup)?.set(data, forKey: self.storageKey)
            }
            if keys.contains(self.groupsKey),
               let data    = NSUbiquitousKeyValueStore.default.data(forKey: self.groupsKey),
               let decoded = try? JSONDecoder().decode([StationGroup].self, from: data) {
                self.groups = decoded
                UserDefaults(suiteName: self.appGroup)?.set(data, forKey: self.groupsKey)
            }
        }
    }
}
