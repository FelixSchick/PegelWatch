import SwiftUI
import TipKit

struct WatchlistView: View {

    @State private var store = StationStore.shared
    @State private var snapshotStore = SnapshotStore.shared
    @State private var router = AppRouter.shared
    @State private var path: [WatchedStation] = []
    @State private var sortBySeverity = false
    @State private var showingSnapshotBuilder = false
    @State private var showingSavedSnapshots = false
    @State private var showingGroupManager = false
    @State private var widgetTip = WidgetTip()
    @State private var groupTip = GroupCreationTip()

    private var displayedStations: [WatchedStation] {
        applySorting(store.watchedStations)
    }

    var body: some View {
        NavigationStack(path: $path) {
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
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(600))
                    let hasStale = store.watchedStations.contains(where: { $0.isStale })
                    let canRefresh = store.lastRefreshed.map { Date().timeIntervalSince($0) > 540 } ?? true
                    if hasStale && canRefresh { await store.refreshAll() }
                }
            }
            .onAppear {
                openPendingStation()
                WidgetTip.hasWatchedStation = !store.watchedStations.isEmpty
                GroupCreationTip.hasGroupedStation = !store.groups.isEmpty
            }
            .onChange(of: router.pendingStationID) { openPendingStation() }
            .onChange(of: store.watchedStations.count) {
                if !store.watchedStations.isEmpty { WidgetTip.hasWatchedStation = true }
            }
            .onChange(of: store.groups) {
                GroupCreationTip.hasGroupedStation = !store.groups.isEmpty
            }
            .refreshable {
                await store.refreshAll()
            }
            .overlay {
                if store.isRefreshing && store.watchedStations.isEmpty {
                    ProgressView("Lade Daten…")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TipView(widgetTip)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                
                TipView(groupTip)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                

            }
            .sheet(isPresented: $showingSnapshotBuilder) {
                SectorSnapshotView(allStations: store.watchedStations)
            }
            .sheet(isPresented: $showingSavedSnapshots) {
                SavedSnapshotsView()
            }
            .sheet(isPresented: $showingGroupManager) {
                GroupManagerSheet()
            }
        }
    }

    /// Öffnet die per Deep-Link (Spotlight) angeforderte Station.
    private func openPendingStation() {
        guard let id = router.pendingStationID,
              let station = store.watchedStations.first(where: { $0.id == id }) else { return }
        router.pendingStationID = nil
        path = [station]
    }

    // MARK: - Sorting

    private func applySorting(_ stations: [WatchedStation]) -> [WatchedStation] {
        guard sortBySeverity else { return stations }
        let order: [AlarmLevel] = [.critical, .danger, .warning, .normal]
        return stations.sorted { a, b in
            let ai = order.firstIndex(of: a.alarmLevel) ?? order.count
            let bi = order.firstIndex(of: b.alarmLevel) ?? order.count
            if ai != bi { return ai < bi }
            return a.shortname < b.shortname
        }
    }

    private func stationsForGroup(_ group: StationGroup) -> [WatchedStation] {
        let ids = Set(group.stationIDs)
        return applySorting(store.watchedStations.filter { ids.contains($0.id) })
    }

    private var ungroupedStations: [WatchedStation] {
        let assignedIDs = Set(store.groups.flatMap(\.stationIDs))
        return applySorting(store.watchedStations.filter { !assignedIDs.contains($0.id) })
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

            if store.groups.isEmpty {
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
            } else {
                groupedListContent
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

    @ViewBuilder
    private var groupedListContent: some View {
        ForEach(store.groups) { group in
            let stations = stationsForGroup(group)
            if !stations.isEmpty {
                Section {
                    ForEach(stations) { station in
                        NavigationLink(value: station) {
                            StationRowView(station: station)
                        }
                        .opacity(station.noDataAvailable ? 0.6 : 1.0)
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            store.remove(id: stations[idx].id)
                        }
                    }
                } header: {
                    Label(group.name, systemImage: group.icon)
                }
            }
        }

        let ungrouped = ungroupedStations
        if !ungrouped.isEmpty {
            Section {
                ForEach(ungrouped) { station in
                    NavigationLink(value: station) {
                        StationRowView(station: station)
                    }
                    .opacity(station.noDataAvailable ? 0.6 : 1.0)
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        store.remove(id: ungrouped[idx].id)
                    }
                }
            } header: {
                Text("Nicht zugeordnet")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Keine Stationen", systemImage: "water.waves.slash")
        } description: {
            Text("Füge Messstationen über den Reiter \"Hinzufügen\" hinzu.")
        } actions: {
            Button("Jetzt hinzufügen") {
                router.selectedTab = .search
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !store.watchedStations.isEmpty {
                Menu {
                    Button {
                        showingSnapshotBuilder = true
                    } label: {
                        Label("Neue Lageübersicht", systemImage: "plus.rectangle")
                    }
                    Button {
                        showingSavedSnapshots = true
                    } label: {
                        let count = snapshotStore.snapshots.count
                        Label(
                            count == 0 ? "Gespeicherte" : "Gespeicherte (\(count))",
                            systemImage: "archivebox"
                        )
                    }
                    Divider()
                    Button {
                        showingGroupManager = true
                    } label: {
                        let count = store.groups.count
                        Label(
                            count == 0 ? "Gruppen verwalten" : "Gruppen (\(count))",
                            systemImage: "folder"
                        )
                    }
                } label: {
                    
                    Image(systemName: "ellipsis")
                }
                .help("Lageübersichten & Gruppen")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation { sortBySeverity.toggle() }
            } label: {
                Image(systemName: sortBySeverity ? "exclamationmark.triangle.fill" : "line.3.horizontal.decrease.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(sortBySeverity ? .orange : .primary)
            }
            .help(sortBySeverity ? "Sortierung: nach Alarmstufe" : "Sortierung: Standard")
            .accessibilityLabel(sortBySeverity ? "Nach Alarmstufe sortiert" : "Standard-Sortierung")
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
            .accessibilityLabel("Pegel aktualisieren")
        }
    }
}

#Preview {
    WatchlistView()
}
