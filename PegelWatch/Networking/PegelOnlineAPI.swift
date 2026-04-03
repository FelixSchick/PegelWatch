import Foundation

actor PegelOnlineAPI {

    static let shared = PegelOnlineAPI()

    private let baseURL = "https://pegelonline.wsv.de/webservices/rest-api/v2"

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
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

    /// Fetches levels for multiple stations concurrently. Failed stations are skipped.
    func fetchLevels(for stationIDs: [String]) async -> [String: Double] {
        await withTaskGroup(of: (String, Double?).self) { group in
            for id in stationIDs {
                group.addTask {
                    do {
                        return (id, try await self.fetchCurrentLevel(for: id))
                    } catch {
                        print("[PegelWatch] ❌ \(id) → \(error.localizedDescription)")
                        return (id, nil)
                    }
                }
            }
            var results: [String: Double] = [:]
            for await (id, value) in group {
                if let v = value { results[id] = v }
            }
            return results
        }
    }

    func fetchAllLevels(for stationUUID: String) async throws -> [(timestamp: Date, value: Double)] {
        let data = try await get(url: makeURL(path: "/stations/\(stationUUID)/W/measurements.json"))
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode([APILevelMeasurement].self, from: data).map { ($0.timestamp, $0.value) }
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
        guard http.statusCode == 200 else { throw PegelAPIError.httpError(http.statusCode) }
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
