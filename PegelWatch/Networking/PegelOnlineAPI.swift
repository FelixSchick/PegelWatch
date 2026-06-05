import Foundation

actor PegelOnlineAPI {

    static let shared = PegelOnlineAPI()

    private let baseURL = "https://pegelonline.wsv.de/webservices/rest-api/v2"

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let historyDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Public API

    func fetchAllStations() async throws -> [Station] {
        let data = try await get(url: makeURL(path: "/stations.json"))
        return try decoder.decode([Station].self, from: data)
    }

    func fetchCurrentLevel(for stationUUID: String) async throws -> Double {
        let data = try await get(url: makeURL(path: "/stations/\(stationUUID)/W/currentmeasurement.json"))
        return try decoder.decode(CurrentMeasurement.self, from: data).value
    }

    /// Fetches levels for multiple stations concurrently.
    /// Returns `levels` for stations with data and `noDataIDs` for stations the API has no measurements for (HTTP 404).
    func fetchLevels(for stationIDs: [String]) async -> (levels: [String: Double], noDataIDs: Set<String>) {
        await withTaskGroup(of: (String, Double?, Bool).self) { group in
            for id in stationIDs {
                group.addTask {
                    do {
                        return (id, try await self.fetchCurrentLevel(for: id), false)
                    } catch PegelAPIError.noData {
                        return (id, nil, true)
                    } catch {
                        print("[PegelWatch] ❌ \(id) → \(error.localizedDescription)")
                        return (id, nil, false)
                    }
                }
            }
            var levels: [String: Double] = [:]
            var noDataIDs: Set<String> = []
            for await (id, value, isNoData) in group {
                if let v = value { levels[id] = v }
                else if isNoData { noDataIDs.insert(id) }
            }
            return (levels, noDataIDs)
        }
    }

    /// Fetches the last 30 days of measurements — the maximum range shown in the chart.
    func fetchAllLevels(for stationUUID: String) async throws -> [(timestamp: Date, value: Double)] {
        let start = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30 * 24 * 3600))
        let data = try await get(url: makeURL(
            path: "/stations/\(stationUUID)/W/measurements.json",
            queryItems: [URLQueryItem(name: "start", value: start)]
        ))
        return try historyDecoder.decode([APILevelMeasurement].self, from: data).map { ($0.timestamp, $0.value) }
    }

    // MARK: - Private

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents(string: baseURL + path)
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw PegelAPIError.invalidURL(path) }
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

// MARK: - Errors

enum PegelAPIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)
    /// HTTP 404 – die Station stellt keine Messdaten bereit
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):  return "Ungültige URL: \(path)"
        case .invalidResponse:       return "Ungültige Server-Antwort"
        case .httpError(let code):   return "HTTP Fehler \(code)"
        case .noData:                return "Keine Messdaten verfügbar"
        }
    }
}
