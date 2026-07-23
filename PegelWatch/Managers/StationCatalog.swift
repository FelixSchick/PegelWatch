import Foundation

/// Session-wide singleton that loads the full station catalog once and caches it
/// to disk so subsequent app launches show data immediately without waiting for the network.
@Observable
@MainActor
final class StationCatalog {

    static let shared = StationCatalog()

    private(set) var stations: [Station] = []
    private(set) var isLoading = false
    private(set) var error: String?

    private var hasStartedLoading = false
    private let cacheURL: URL

    private init() {
        // init() must stay fast — disk read happens async in loadIfNeeded()
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheURL = caches.appendingPathComponent("station_catalog.json")
    }

    /// Triggers a background load the first time it is called per session.
    /// Reads disk cache first (off main thread), then refreshes from network.
    func loadIfNeeded() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        isLoading = true
        Task { await loadCacheAndFetch() }
    }

    /// Forces a new network fetch (e.g. after an error, or from the dev menu).
    func reload() {
        hasStartedLoading = false
        stations = []
        loadIfNeeded()
    }

    // MARK: - Private

    private func loadCacheAndFetch() async {
        // Read disk cache off the main thread so the app never freezes on launch
        let url = cacheURL
        let cached: [Station]? = await Task.detached(priority: .userInitiated) { () -> [Station]? in
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([Station].self, from: data)
            else { return nil }
            return decoded
        }.value
        if let cached, !cached.isEmpty {
            stations = cached
        }
        await fetchFresh()
    }

    private func fetchFresh() async {
        defer { isLoading = false }
        error = nil

        do {
            async let germanFetch = PegelOnlineAPI.shared.fetchAllStations()
            async let luxFetch   = HeichwaasserAPI.shared.fetchAllStations()

            var result = try await germanFetch
            if let lux = try? await luxFetch { result.append(contentsOf: lux) }

            // Sort off the main thread — 4500+ comparisons would cause a visible hitch
            let sorted = await Task.detached(priority: .userInitiated) {
                result.sorted {
                    $0.water.shortname == $1.water.shortname
                        ? $0.shortname < $1.shortname
                        : $0.water.shortname < $1.water.shortname
                }
            }.value

            stations = sorted
            writeToDisk(sorted)
        } catch {
            if stations.isEmpty {
                self.error = error.localizedDescription
            }
            // If cached data is already showing, swallow the error silently
        }
    }

    private func writeToDisk(_ stations: [Station]) {
        let url = cacheURL
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(stations) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
