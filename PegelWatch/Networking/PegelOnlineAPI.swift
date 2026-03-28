import Foundation

/// Actor-based API client for PegelOnline WSV REST API.
/// `actor` guarantees thread safety — no race conditions when called from multiple async tasks.
actor PegelOnlineAPI {

    static let shared = PegelOnlineAPI()

    private let baseURL = "https://pegelonline.wsv.de/webservices/rest-api/v2"

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // Automatically maps snake_case JSON keys to camelCase Swift properties
        // e.g. "current_measurement" → "currentMeasurement"
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - Public API

    /// Loads all ~4000 stations from PegelOnline.
    func fetchAllStations() async throws -> [Station] {
        let url = try makeURL(path: "/stations.json")
        let data = try await get(url: url)
        return try decoder.decode([Station].self, from: data)
    }

    /// Loads the current water level for one station.
    /// /currentmeasurement.json returns a CurrentMeasurement object directly — not wrapped in anything.
    func fetchCurrentLevel(for stationUUID: String) async throws -> Double {
        let path = "/stations/\(stationUUID)/W/currentmeasurement.json"
        let url = try makeURL(path: path)
        let data = try await get(url: url)
        let measurement = try decoder.decode(CurrentMeasurement.self, from: data)
        return measurement.value
    }

    /// Fetches current levels for multiple stations concurrently.
    /// Returns a dictionary [stationID: levelInCm].
    /// Each failed station is logged and skipped — won't block the others.
    func fetchLevels(for stationIDs: [String]) async -> [String: Double] {
        // withTaskGroup = Parallel.ForEach in C# — all requests run at the same time
        await withTaskGroup(of: (String, Double?).self) { group in
            for id in stationIDs {
                group.addTask {
                    do {
                        let value = try await self.fetchCurrentLevel(for: id)
                        print("[PegelWatch] ✅ \(id) → \(value) cm")
                        return (id, value)
                    } catch {
                        print("[PegelWatch] ❌ \(id) → \(error.localizedDescription)")
                        return (id, nil)
                    }
                }
            }
            var results: [String: Double] = [:]
            for await (id, value) in group {
                if let v = value {
                    results[id] = v
                }
            }
            print("[PegelWatch] fetchLevels done — \(results.count)/\(stationIDs.count) values received")
            return results
        }
    }
    
    func fetchAllLevels(for stationUUID: String) async throws -> [(timestamp: Date, value: Double)] {
        let path = "/stations/\(stationUUID)/W/measurements.json"
        let url = try makeURL(path: path)
        let data = try await get(url: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let measurements = try decoder.decode([APILevelMeasurement].self, from: data)

        return measurements.map { ($0.timestamp, $0.value) }
    }

    // MARK: - Private Helpers

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents(string: baseURL + path)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw PegelAPIError.invalidURL(path)
        }
        return url
    }

    private func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("PegelWatch/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw PegelAPIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw PegelAPIError.httpError(http.statusCode)
        }
        return data
    }
}

// MARK: - Errors

enum PegelAPIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):  return "Ungültige URL: \(path)"
        case .invalidResponse:       return "Ungültige Server-Antwort"
        case .httpError(let code):   return "HTTP Fehler \(code)"
        }
    }
}
