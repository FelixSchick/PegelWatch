import SwiftUI

struct StationSearchView: View {

    @State private var store = StationStore.shared
    @State private var allStations: [Station] = []
    @State private var searchText: String = ""
    @State private var debouncedSearch: String = ""
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var selectedRegion: String = "Alle"

    // Cached values — recomputed only when their inputs change, not on every render
    @State private var availableWaters: [String] = ["Alle"]
    @State private var filteredStations: [Station] = []

    private static let majorWaters: Set<String> = [
        "RHEIN", "MOSEL", "ELBE", "DONAU", "WESER", "MAIN", "NECKAR",
         "SAAR", "FULDA",
        "SAUER", "OUR", "ALZETTE",
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let error = loadError {
                    errorView(error)
                } else {
                    searchResultsList
                }
            }
            .navigationTitle("Stationen")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Station oder Gewässer suchen"
            )
            .task {
                guard allStations.isEmpty else { return }
                await loadStations()
            }
            // Debounce: wait 250 ms after the last keystroke before filtering
            .onChange(of: searchText) { _, new in
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard searchText == new else { return }
                    debouncedSearch = new
                }
            }
            .onChange(of: debouncedSearch) { updateFilteredStations() }
            .onChange(of: selectedRegion)  { updateFilteredStations() }
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Lade alle Messstationen…")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text("(Deutschland & Luxemburg)")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Fehler beim Laden", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Erneut versuchen") {
                Task { await loadStations() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var searchResultsList: some View {
        List {
            if debouncedSearch.isEmpty {
                Section {
                    Picker("Gewässer", selection: $selectedRegion) {
                        ForEach(availableWaters, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section(header: Text(resultHeader)) {
                if selectedRegion != "Alle" && debouncedSearch.isEmpty && filteredStations.allSatisfy({ $0.km != nil }) {
                    RiverStationView(
                        stations: filteredStations,
                        isWatched: { store.isWatching($0) },
                        onToggle: toggleWatch
                    )
                    .frame(height: CGFloat(filteredStations.count) * 80 + 64)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredStations.prefix(200)) { station in
                        SearchResultRow(
                            station: station,
                            isWatched: store.isWatching(station.id),
                            onToggle: { toggleWatch(station) }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: selectedRegion)
    }

    private var resultHeader: String {
        let total = filteredStations.count
        let shown = min(total, 200)
        if total > 200 {
            return "\(shown) von \(total) Stationen (suche verfeinern)"
        }
        return "\(total) Station\(total == 1 ? "" : "en")"
    }

    // MARK: - Filtering

    private func updateFilteredStations() {
        var result = allStations

        if selectedRegion != "Alle" {
            result = result.filter { $0.water.shortname == selectedRegion }
        }

        if !debouncedSearch.isEmpty {
            let query = debouncedSearch.uppercased()
            result = result.filter {
                $0.shortname.contains(query) ||
                $0.longname.uppercased().contains(query) ||
                $0.water.shortname.contains(query) ||
                $0.water.longname.uppercased().contains(query) ||
                $0.agency.uppercased().contains(query)
            }
        }

        result.sort { $0.km ?? 0.0 < $1.km ?? 0.0 }
        filteredStations = result
    }

    // MARK: - Actions

    private func loadStations() async {
        isLoading = true
        loadError = nil

        async let germanFetch = PegelOnlineAPI.shared.fetchAllStations()
        async let luxFetch = HeichwaasserAPI.shared.fetchAllStations()

        var stations: [Station]
        do {
            stations = try await germanFetch
        } catch {
            loadError = error.localizedDescription
            isLoading = false
            return
        }

        if let luxStations = try? await luxFetch {
            stations.append(contentsOf: luxStations)
        }

        stations.sort {
            if $0.water.shortname != $1.water.shortname {
                return $0.water.shortname < $1.water.shortname
            }
            return $0.shortname < $1.shortname
        }
        allStations = stations
        let allWaterNames = Set(stations.map { $0.water.shortname })
        availableWaters = ["Alle"] + allWaterNames.filter { Self.majorWaters.contains($0) }.sorted()
        updateFilteredStations()
        isLoading = false
    }

    private func toggleWatch(_ station: Station) {
        if store.isWatching(station.id) {
            store.remove(id: station.id)
        } else {
            store.add(WatchedStation(from: station))
            Task {
                if HeichwaasserAPI.isLuxembourgStation(station.id) {
                    let result = await HeichwaasserAPI.shared.fetchLevels(for: [station.id])
                    if let value = result.levels[station.id] {
                        store.updateLevel(id: station.id, value: value)
                    }
                } else {
                    let result = await PegelOnlineAPI.shared.fetchLevels(for: [station.id])
                    if let value = result.levels[station.id] {
                        store.updateLevel(id: station.id, value: value)
                    }
                }
            }
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {

    let station: Station
    let isWatched: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isWatched ? Color.accentColor.opacity(0.12) : Color.blue.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: "water.waves")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isWatched ? Color.accentColor : .blue.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(station.displayShortname)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(station.water.longname.isEmpty ? station.water.shortname : station.water.longname)
                        .font(.caption)
                    if let km = station.km {
                        Text("·").foregroundStyle(.tertiary)
                        Text("km \(Int(km))").font(.caption)
                    }
                }
                .foregroundStyle(.secondary)

                Text(station.agency)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: onToggle) {
                Image(systemName: isWatched ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isWatched ? .green : .accentColor)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.spring, value: isWatched)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    StationSearchView()
}
