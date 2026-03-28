import SwiftUI

struct StationSearchView: View {

    @State private var store = StationStore.shared
    @State private var allStations: [Station] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var selectedRegion: String = "Alle"

    // Filtered results — computed from search text and region
    private var filteredStations: [Station] {
        var result = allStations

        if selectedRegion != "Alle" {
            result = result.filter { $0.water.shortname == selectedRegion }
        }

        if !searchText.isEmpty {
            let query = searchText.uppercased()
            result = result.filter {
                $0.shortname.contains(query) ||
                $0.longname.uppercased().contains(query) ||
                $0.water.shortname.contains(query) ||
                $0.water.longname.uppercased().contains(query) ||
                $0.agency.uppercased().contains(query)
            }
        }
        
        result.sort {
            $0.km ?? 0.0 < $1.km ?? 0.0
        }

        return result
    }

    // All unique water names for the filter picker
    private var availableWaters: [String] {
        let names = Set(allStations.map { $0.water.shortname }).sorted()
        return ["Alle"] + names
    }

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
                // Load once — all ~4000 stations
                guard allStations.isEmpty else { return }
                await loadStations()
            }
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
            Text("(ca. 4.000 Stationen bundesweit)")
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
            if searchText.isEmpty {
                Section {
                    Picker("Gewässer", selection: $selectedRegion) {
                        ForEach(availableWaters, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section(header: Text(resultHeader)) {
                if selectedRegion != "Alle" && searchText.isEmpty {
                    // River visualization — takes the full section space
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
        let count = min(filteredStations.count, 200)
        let total = filteredStations.count
        if total > 200 {
            return "\(count) von \(total) Stationen (suche verfeinern)"
        }
        return "\(total) Station\(total == 1 ? "" : "en")"
    }

    // MARK: - Actions

    private func loadStations() async {
        isLoading = true
        loadError = nil
        do {
            allStations = try await PegelOnlineAPI.shared.fetchAllStations()
            // Sort alphabetically by water, then by station name
            allStations.sort {
                if $0.water.shortname != $1.water.shortname {
                    return $0.water.shortname < $1.water.shortname
                }
                return $0.shortname < $1.shortname
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleWatch(_ station: Station) {
        if store.isWatching(station.id) {
            store.remove(id: station.id)
        } else {
            store.add(WatchedStation(from: station))
            // Immediately fetch its level
            Task {
                let levels = await PegelOnlineAPI.shared.fetchLevels(for: [station.uuid])
                if let value = levels[station.uuid] {
                    store.updateLevel(id: station.uuid, value: value)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(station.shortname)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(station.water.longname.isEmpty ? station.water.shortname : station.water.longname)
                        .font(.caption)
                    if let km = station.km {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("km \(Int(km))")
                            .font(.caption)
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
