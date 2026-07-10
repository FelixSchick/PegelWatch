import Foundation

/// Lädt die Watchlist aus dem App-Group-Container — geschrieben von der
/// iPhone-App / dem Widget. Bringt anschließend die Pegel-Werte über die
/// beiden Netzwerk-APIs auf den aktuellen Stand.
///
/// Alternative wäre WatchConnectivity, das aber Session-Setup und
/// erreichbare iPhone-App voraussetzt. Reines UserDefaults + Netzwerk ist
/// robuster für einen reinen "Read-only"-Watch-Client.
enum WatchStationLoader {
    private static let suiteName = "group.de.felixschick.pegelwatch"
    private static let key = "de.felixschick.pegelwatch.watched_stations"

    static func load() -> [WatchedStation] {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([WatchedStation].self, from: data)
        else { return [] }
        return decoded
    }

    static func fetchFresh() async -> [WatchedStation] {
        var stations = load()
        let ids = stations.map(\.id)
        guard !ids.isEmpty else { return stations }

        let pegelIDs = ids.filter { !HeichwaasserAPI.isLuxembourgStation($0) }
        let luxIDs = ids.filter { HeichwaasserAPI.isLuxembourgStation($0) }

        async let pegelResult = PegelOnlineAPI.shared.fetchLevels(for: pegelIDs)
        async let luxResult = HeichwaasserAPI.shared.fetchLevels(for: luxIDs)

        let (pegelData, luxData) = await (pegelResult, luxResult)
        var levels = pegelData.levels
        for (id, value) in luxData.levels { levels[id] = value }

        for i in stations.indices {
            if let v = levels[stations[i].id] {
                stations[i].previousValue = stations[i].lastValue
                stations[i].lastValue = v
                stations[i].lastUpdated = Date()
            }
        }

        // Zurückschreiben — die iPhone-App sieht den frischen Stand beim
        // nächsten `load()` und auch die Widgets ziehen sich neu.
        if let encoded = try? JSONEncoder().encode(stations) {
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.set(encoded, forKey: key)
        }

        return stations
    }
}
