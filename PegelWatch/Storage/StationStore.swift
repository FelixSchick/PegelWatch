import Foundation
import Observation

/// Central data store for the app.
/// @Observable is the modern iOS 17 equivalent of @ObservableObject.
/// Any SwiftUI view that reads a property automatically re-renders when it changes.
@Observable
class StationStore {

    static let shared = StationStore()

    // MARK: - State

    var watchedStations: [WatchedStation] = [] {
        didSet { persist() }   // didSet runs after every change — like a property setter
    }

    var isRefreshing: Bool = false
    var lastError: String?

    // MARK: - Init

    init() {
        load()
    }

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
        watchedStations[idx].lastValue = value
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

            // Alarm check
            if let station = watchedStations.first(where: { $0.id == id }),
               station.alarmEnabled,
               let threshold = station.alarmThreshold,
               value >= threshold {
                NotificationManager.shared.sendAlarmNotification(for: station, currentValue: value)
            }
        }
    }

    // MARK: - Persistence (UserDefaults)

    private let storageKey = "de.felixschick.pegelwatch.watched_stations"

    private func persist() {
        guard let data = try? JSONEncoder().encode(watchedStations) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([WatchedStation].self, from: data)
        else { return }
        watchedStations = decoded
    }
}
