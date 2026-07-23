import SwiftUI

struct StationSearchView: View {

    @State private var store = StationStore.shared
    @State private var catalog = StationCatalog.shared
    @State private var searchText: String = ""
    @State private var debouncedSearch: String = ""
    @State private var selectedRegion: String = "Alle"

    // Derived state — updated asynchronously to avoid blocking the main thread
    @State private var availableWaters: [String] = ["Alle"]
    @State private var filteredStations: [Station] = []
    @State private var filterTask: Task<Void, Never>?

    // Guidance: 0 = choose filter/search, 1 = tap +, 2 = done
    @AppStorage("searchGuidanceStep") private var searchGuidanceStep = 0
    @State private var initialWatchedCount = 0

    private static let majorWaters: Set<String> = [
        "RHEIN", "MOSEL", "ELBE", "DONAU", "WESER", "MAIN", "NECKAR",
        "SAAR", "FULDA", "SAUER", "OUR", "ALZETTE",
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let error = catalog.error, catalog.stations.isEmpty {
                    errorView(error)
                } else {
                    // List is always shown so the search bar stays interactive during loading
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
                initialWatchedCount = store.watchedStations.count
                catalog.loadIfNeeded()
                // Disk cache may already be available — prime derived state immediately
                if !catalog.stations.isEmpty {
                    updateAvailableWaters()
                    updateFilteredStations()
                }
            }
            // When catalog data arrives (disk cache or network), refresh derived state
            .onChange(of: catalog.stations.count) {
                updateAvailableWaters()
                updateFilteredStations()
            }
            // Debounce: wait 250 ms after last keystroke before filtering
            .onChange(of: searchText) { _, new in
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard searchText == new else { return }
                    debouncedSearch = new
                }
                if searchGuidanceStep == 0 && !new.isEmpty {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        searchGuidanceStep = 1
                    }
                }
            }
            .onChange(of: selectedRegion) {
                updateFilteredStations()
                if searchGuidanceStep == 0 && selectedRegion != "Alle" {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        searchGuidanceStep = 1
                    }
                }
            }
            .onChange(of: debouncedSearch) { updateFilteredStations() }
            // Step 1 → 2: user added their first station this session
            .onChange(of: store.watchedStations.count) {
                if store.watchedStations.count > initialWatchedCount && searchGuidanceStep == 1 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        searchGuidanceStep = 2
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if searchGuidanceStep < 2 && !catalog.stations.isEmpty {
                    searchGuidanceCard
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: searchGuidanceStep)
        }
    }

    // MARK: - Guidance Card

    @ViewBuilder
    private var searchGuidanceCard: some View {
        switch searchGuidanceStep {
        case 0:
            GuidanceCard(
                icon: "hand.tap",
                iconColor: .indigo,
                message: "Wähle ein Gewässer aus dem Menü oder gib einen Stationsnamen ein.",
                onDismiss: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        searchGuidanceStep = 2
                    }
                }
            )
        case 1:
            GuidanceCard(
                icon: "plus.circle",
                iconColor: .green,
                message: "Tippe auf + neben einer Station, um sie deiner Watchlist hinzuzufügen.",
                onDismiss: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        searchGuidanceStep = 2
                    }
                }
            )
        default:
            EmptyView()
        }
    }

    // MARK: - Views

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Fehler beim Laden", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Erneut versuchen") {
                catalog.reload()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var searchResultsList: some View {
        List {
            // Inline loading row — list stays interactive while the catalog arrives
            if catalog.isLoading && catalog.stations.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Lade alle Messstationen…")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }

            if !catalog.stations.isEmpty {
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

    private func updateAvailableWaters() {
        let allWaterNames = Set(catalog.stations.map { $0.water.shortname })
        availableWaters = ["Alle"] + allWaterNames.filter { Self.majorWaters.contains($0) }.sorted()
    }

    private func updateFilteredStations() {
        filterTask?.cancel()
        let stations = catalog.stations
        let region = selectedRegion
        let query = debouncedSearch.uppercased()
        // Watched rivers surface first — avoids needing to search for familiar waters
        let watchedWaters = Set(store.watchedStations.map { $0.waterShortname })

        filterTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                var r = stations

                if region != "Alle" {
                    r = r.filter { $0.water.shortname == region }
                }

                if !query.isEmpty {
                    r = r.filter {
                        $0.shortname.contains(query) ||
                        $0.longname.uppercased().contains(query) ||
                        $0.water.shortname.contains(query) ||
                        $0.water.longname.uppercased().contains(query) ||
                        $0.agency.uppercased().contains(query)
                    }
                }

                r.sort { a, b in
                    if region == "Alle" {
                        // Watched rivers appear first, then alphabetical by water name
                        let aw = watchedWaters.contains(a.water.shortname)
                        let bw = watchedWaters.contains(b.water.shortname)
                        if aw != bw { return aw }
                        if a.water.shortname != b.water.shortname {
                            return a.water.shortname < b.water.shortname
                        }
                    }
                    // Within a river, sort by km so stations appear in flow order
                    return (a.km ?? .infinity) < (b.km ?? .infinity)
                }

                return r
            }.value

            guard !Task.isCancelled else { return }
            filteredStations = result
        }
    }

    // MARK: - Actions

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
