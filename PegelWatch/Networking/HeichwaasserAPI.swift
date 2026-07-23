import Foundation

/// Einheitlicher Einstiegspunkt für Pegel-Abfragen über beide Datenquellen
/// (PEGELONLINE für DE, Héichwaasser.lu für LU). Wird von App-Detailansicht,
/// Widget und Siri-Intent gemeinsam genutzt, damit das Quellen-Routing nur
/// an einer Stelle lebt.
enum LevelDataProvider {

    static func history(for stationID: String, days: Int = 30) async throws -> [(timestamp: Date, value: Double)] {
        if HeichwaasserAPI.isLuxembourgStation(stationID) {
            let full = try await HeichwaasserAPI.shared.fetchHistory(for: stationID)
            let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
            return full.filter { $0.timestamp >= cutoff }
        }
        return try await PegelOnlineAPI.shared.fetchAllLevels(for: stationID, days: days)
    }

    static func currentLevel(for stationID: String) async -> Double? {
        if HeichwaasserAPI.isLuxembourgStation(stationID) {
            return await HeichwaasserAPI.shared.fetchLevels(for: [stationID]).levels[stationID]
        }
        return await PegelOnlineAPI.shared.fetchLevels(for: [stationID]).levels[stationID]
    }
}

actor HeichwaasserAPI {

    static let shared = HeichwaasserAPI()

    private let baseURL = "https://heichwaasser.lu/api/v1"

    static let stationIDPrefix = "lu-"

    static func isLuxembourgStation(_ id: String) -> Bool {
        id.hasPrefix(stationIDPrefix)
    }

    private static func heichwaasserID(from stationID: String) -> String? {
        guard stationID.hasPrefix(stationIDPrefix) else { return nil }
        return String(stationID.dropFirst(stationIDPrefix.count))
    }

    private static let riverNameMapping: [String: String] = [
        "Moselle": "MOSEL",
        "Sûre": "SAUER",
        "Alzette": "ALZETTE",
        "Our": "OUR",
        "Attert": "ATTERT",
        "Wark": "WARK",
        "Clerve": "CLERVE",
        "Wiltz": "WILTZ",
        "Eisch": "EISCH",
        "Mamer": "MAMER",
        "Ernz Blanche": "ERNZ BLANCHE",
        "Ernz Noire": "ERNZ NOIRE",
        "Syre": "SYRE",
        "Gander": "GANDER",
        "Chiers": "CHIERS",
    ]

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Response Models

    private struct LuxStation: Decodable {
        let id: Int
        let river: LuxRiver
        let city: String
        let latitude: Double
        let longitude: Double
        let trend: String
        let current: LuxMeasurement
        let measurements: [LuxMeasurement]?

        enum CodingKeys: String, CodingKey {
            case id, river, city, latitude, longitude, trend, current, measurements
        }
    }

    private struct LuxRiver: Decodable {
        let id: Int
        let name: String
    }

    private struct LuxMeasurement: Decodable {
        let timestamp: String
        let value: Double
        let unit: String
    }

    // MARK: - Public API

    func fetchAllStations() async throws -> [Station] {
        let data = try await get(url: makeURL(path: "/stations"))
        let luxStations = try JSONDecoder().decode([LuxStation].self, from: data)
        return luxStations
            .filter { $0.current.unit == "cm" }
            .map(Self.convertToStation)
    }

    func fetchLevels(for stationIDs: [String]) async -> (levels: [String: Double], noDataIDs: Set<String>) {
        guard !stationIDs.isEmpty else { return ([:], []) }

        do {
            let data = try await get(url: makeURL(path: "/stations"))
            let luxStations = try JSONDecoder().decode([LuxStation].self, from: data)

            let stationIDSet = Set(stationIDs)
            var levels: [String: Double] = [:]
            var noDataIDs: Set<String> = []

            let allLevels: [String: Double] = luxStations
                .filter { $0.current.unit == "cm" }
                .reduce(into: [:]) { dict, s in
                    dict["\(Self.stationIDPrefix)\(s.id)"] = s.current.value
                }

            for id in stationIDSet {
                if let value = allLevels[id] {
                    levels[id] = value
                } else {
                    noDataIDs.insert(id)
                }
            }

            return (levels, noDataIDs)
        } catch {
            print("[PegelWatch] ❌ Luxembourg: \(error.localizedDescription)")
            return ([:], [])
        }
    }

    func fetchHistory(for stationID: String) async throws -> [(timestamp: Date, value: Double)] {
        guard let hID = Self.heichwaasserID(from: stationID) else {
            throw PegelAPIError.invalidURL(stationID)
        }
        let endTime = Int(Date().timeIntervalSince1970)
        let startTime = endTime - 30 * 24 * 3600
        let data = try await get(url: makeURL(path: "/stations/\(hID)/start/\(startTime)/end/\(endTime)"))
        let station = try JSONDecoder().decode(LuxStation.self, from: data)

        return (station.measurements ?? []).compactMap { m in
            guard let date = Self.timestampFormatter.date(from: m.timestamp) else { return nil }
            return (timestamp: date, value: m.value)
        }.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Private

    private static func convertToStation(_ lux: LuxStation) -> Station {
        let germanName = riverNameMapping[lux.river.name] ?? lux.river.name.uppercased()
        return Station(
            uuid: "\(stationIDPrefix)\(lux.id)",
            number: String(lux.id),
            shortname: lux.city.uppercased(),
            longname: lux.city,
            km: nil,
            agency: "Administration de la gestion de l'eau",
            longitude: lux.longitude,
            latitude: lux.latitude,
            water: WaterInfo(shortname: germanName, longname: germanName)
        )
    }

    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw PegelAPIError.invalidURL(path)
        }
        return url
    }

    private func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("PegelWatch/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PegelAPIError.invalidResponse }
        if http.statusCode == 404 { throw PegelAPIError.noData }
        guard http.statusCode == 200 else { throw PegelAPIError.httpError(http.statusCode) }
        return data
    }
}
