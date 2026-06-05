import SwiftUI

struct WatchlistView: View {

    @State private var store = StationStore.shared
    @State private var sortBySeverity = false

    private var displayedStations: [WatchedStation] {
        guard sortBySeverity else { return store.watchedStations }
        return store.watchedStations.sorted { a, b in
            let order: [AlarmLevel] = [.critical, .danger, .warning, .normal]
            let ai = order.firstIndex(of: a.alarmLevel) ?? order.count
            let bi = order.firstIndex(of: b.alarmLevel) ?? order.count
            if ai != bi { return ai < bi }
            return a.shortname < b.shortname
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.watchedStations.isEmpty {
                    emptyState
                } else {
                    stationList
                }
            }
            .navigationTitle("PegelWatch")
            .toolbar { toolbarContent }
            .task {
                await store.refreshAll()
            }
            .refreshable {
                await store.refreshAll()
            }
            .overlay {
                if store.isRefreshing && store.watchedStations.isEmpty {
                    ProgressView("Lade Daten…")
                }
            }
        }
    }

    // MARK: - Subviews

    private var stationList: some View {
        List {
            if let error = store.lastError {
                Section {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }

            ForEach(displayedStations) { station in
                NavigationLink(value: station) {
                    StationRowView(station: station)
                }
                .opacity(station.noDataAvailable ? 0.6 : 1.0)
            }
            .onDelete { indexSet in
                for idx in indexSet {
                    store.remove(id: displayedStations[idx].id)
                }
            }

            if let refreshed = store.lastRefreshed {
                Section {
                    HStack {
                        Spacer()
                        Label(
                            "Aktualisiert \(refreshed.formatted(.relative(presentation: .named)))",
                            systemImage: "checkmark.circle"
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationDestination(for: WatchedStation.self) { station in
            StationDetailView(station: station)
        }
        .animation(.default, value: store.watchedStations)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Keine Stationen", systemImage: "water.waves.slash")
        } description: {
            Text("Füge Messstationen über den Reiter \"Hinzufügen\" hinzu.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation { sortBySeverity.toggle() }
            } label: {
                Image(systemName: sortBySeverity ? "exclamationmark.triangle.fill" : "line.3.horizontal.decrease.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(sortBySeverity ? .orange : .primary)
            }
            .help(sortBySeverity ? "Sortierung: nach Alarmstufe" : "Sortierung: Standard")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await store.refreshAll() }
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(store.isRefreshing)
        }
    }
}

#Preview {
    WatchlistView()
}
