import SwiftUI

struct WatchlistView: View {

    @State private var store = StationStore.shared

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

            ForEach(store.watchedStations) { station in
                NavigationLink(value: station) {
                    StationRowView(station: station)
                }
            }
            .onDelete { indexSet in
                for idx in indexSet {
                    store.remove(id: store.watchedStations[idx].id)
                }
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
            Text("Füge Messstationen über den Reiter \"Suchen\" hinzu.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
