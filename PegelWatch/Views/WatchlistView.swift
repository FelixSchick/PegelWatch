import SwiftUI
import TipKit

struct WatchlistView: View {

    /// Collection-ID für die flache Liste (keine Gruppen) bzw. für die
    /// "Nicht zugeordnet"-Section, wenn Gruppen existieren.
    private static let ungroupedCollectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @State private var store = StationStore.shared
    @State private var snapshotStore = SnapshotStore.shared
    @State private var router = AppRouter.shared
    @Environment(\.undoManager) private var undoManager
    @State private var path: [WatchedStation] = []
    @State private var sortBySeverity = false
    @State private var showingSnapshotBuilder = false
    @State private var showingSavedSnapshots = false
    @State private var showingGroupManager = false
    @State private var tips = TipGroup(.ordered) {
        WidgetTip()
        GroupCreationTip()
    }

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
                // Immer nur einen Tipp gleichzeitig zeigen
                TipView(tips.currentTip)
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
                    Button("Erneut versuchen") {
                        Task { await store.refreshAll() }
                    }
                    .font(.footnote)
                    .disabled(store.isRefreshing)
                }
            }

            if store.groups.isEmpty {
                ForEach(displayedStations) { station in
                    stationRow(station)
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        store.remove(id: displayedStations[idx].id, undoManager: undoManager)
                    }
                }
                .reorderableRows(collectionID: Self.ungroupedCollectionID, sortLocked: sortBySeverity) { indexSet, newOffset in
                    handleMove(in: displayedStations, indexSet: indexSet, newOffset: newOffset)
                }
            } else {
                groupedListContent
            }

            if let refreshed = store.lastRefreshed {
                Section {
                    HStack {
                        Spacer()
                        // Häkchen nur, wenn der letzte Versuch geklappt hat
                        Label(
                            "Aktualisiert \(refreshed.formatted(.relative(presentation: .named)))",
                            systemImage: store.lastError == nil ? "checkmark.circle" : "exclamationmark.circle"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationDestination(for: WatchedStation.self) { station in
            StationDetailView(station: station)
        }
        .reorderContainerIfAvailable { sources, targetID, collectionID in
            let groupTarget: StationStore.GroupTarget
            if store.groups.isEmpty {
                groupTarget = .unchanged
            } else if collectionID == Self.ungroupedCollectionID {
                groupTarget = .group(nil)
            } else {
                groupTarget = .group(collectionID)
            }
            store.moveWatchedStations(sources, before: targetID, toGroup: groupTarget)
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
                        stationRow(station)
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            store.remove(id: stations[idx].id, undoManager: undoManager)
                        }
                    }
                    .reorderableRows(collectionID: group.id, sortLocked: sortBySeverity) { indexSet, newOffset in
                        handleMove(in: stations, indexSet: indexSet, newOffset: newOffset)
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
                    stationRow(station)
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        store.remove(id: ungrouped[idx].id, undoManager: undoManager)
                    }
                }
                .reorderableRows(collectionID: Self.ungroupedCollectionID, sortLocked: sortBySeverity) { indexSet, newOffset in
                    handleMove(in: ungrouped, indexSet: indexSet, newOffset: newOffset)
                }
            } header: {
                Text("Nicht zugeordnet")
            }
        }
    }

    // MARK: - Row

    private func stationRow(_ station: WatchedStation) -> some View {
        NavigationLink(value: station) {
            StationRowView(station: station)
        }
        .swipeActions(edge: .leading) {
            muteButton(for: station)
                .tint(.orange)
        }
        .contextMenu {
            muteButton(for: station)
            Divider()
            Button(role: .destructive) {
                store.remove(id: station.id, undoManager: undoManager)
            } label: {
                Label("Entfernen", systemImage: "trash")
            }
        } preview: {
            // Flexible statt fester Breite (iPad, Split View, iPhone Duo)
            StationRowView(station: station)
                .padding()
                .frame(minWidth: 280, idealWidth: 360, maxWidth: 420)
        }
    }

    /// Schaltet Mitteilungen der Station für eine Stunde stumm bzw. hebt das auf.
    @ViewBuilder
    private func muteButton(for station: WatchedStation) -> some View {
        if station.isAlarmMuted {
            Button {
                store.unmuteAlarms(for: station.id)
            } label: {
                Label("Stumm aufheben", systemImage: "bell")
            }
        } else {
            Button {
                store.muteAlarms(for: station.id, duration: AlarmMuteDuration.oneHour.seconds)
            } label: {
                Label("1 Std. stumm", systemImage: "bell.slash")
            }
            .disabled(!station.alarmEnabled || station.noDataAvailable)
        }
    }

    // MARK: - Reordering

    /// Übersetzt eine `onMove`-Geste (iOS-Fallback vor `.reorderable()`) in einen
    /// Aufruf von `StationStore.moveWatchedStations`, bezogen auf die angezeigte
    /// Teilmenge `subset` (eine Section oder die flache Liste).
    private func handleMove(in subset: [WatchedStation], indexSet: IndexSet, newOffset: Int) {
        var ids = subset.map(\.id)
        let movedIDs = indexSet.map { ids[$0] }
        ids.move(fromOffsets: indexSet, toOffset: newOffset)
        guard let anchor = movedIDs.first, let newPos = ids.firstIndex(of: anchor) else { return }
        let targetID: String? = (newPos + movedIDs.count) < ids.count ? ids[newPos + movedIDs.count] : nil
        store.moveWatchedStations(movedIDs, before: targetID)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Keine Stationen", systemImage: "water.waves.slash")
        } description: {
            Text("Suche nach einer Messstation an deinem Fluss, um ihren Pegel hier zu verfolgen.")
        } actions: {
            Button("Station suchen") {
                router.selectedTab = .search
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !store.watchedStations.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $sortBySeverity.animation()) {
                        Label("Eigene Reihenfolge", systemImage: "line.3.horizontal").tag(false)
                        Label("Nach Alarmstufe", systemImage: "exclamationmark.triangle").tag(true)
                    } label: {
                        Text("Sortierung")
                    }
                    .pickerStyle(.inline)

                    Section("Lageübersicht") {
                        Button {
                            showingSnapshotBuilder = true
                        } label: {
                            Label("Neue Lageübersicht", systemImage: "plus.rectangle.on.rectangle")
                        }
                        Button {
                            showingSavedSnapshots = true
                        } label: {
                            Label("Gespeicherte", systemImage: "archivebox")
                            let count = snapshotStore.snapshots.count
                            if count > 0 { Text("\(count)") }
                        }
                    }

                    Button {
                        showingGroupManager = true
                    } label: {
                        Label("Gruppen verwalten", systemImage: "folder")
                        let count = store.groups.count
                        if count > 0 { Text("\(count)") }
                    }
                } label: {
                    Label("Mehr", systemImage: "ellipsis")
                }
                .accessibilityLabel("Sortierung, Lageübersichten und Gruppen")
            }
        }
    }
}

#Preview {
    WatchlistView()
}

// MARK: - Reorder availability helpers
//
// SwiftUI's `.reorderable()` / `.reorderContainer(for:in:)` (drag-to-reorder in any
// container, including List sections) require iOS 27. The deployment target here is
// iOS 26.2/26.4, so both call sites fall back to the classic `.onMove(perform:)` on
// older OS versions instead of dropping the feature.

private extension DynamicViewContent {
    /// Marks rows as drag-to-reorder on iOS 27+, or falls back to `.onMove` below it.
    /// Reordering is entirely disabled while `sortLocked` is true, since the displayed
    /// order wouldn't match the stored order in that case.
    @ViewBuilder
    func reorderableRows(collectionID: UUID, sortLocked: Bool, fallbackMove: @escaping (IndexSet, Int) -> Void) -> some View {
        if sortLocked {
            self
        } else if #available(iOS 27.0, *) {
            self.reorderable(collectionID: collectionID)
        } else {
            self.onMove(perform: fallbackMove)
        }
    }
}

private extension View {
    /// Attaches the iOS 27 multi-collection reorder container to a `List`, translating
    /// the resulting `ReorderDifference` into plain `(sources, targetID, collectionID)`
    /// values so the call site doesn't need to import the gated SwiftUI types itself.
    /// A no-op on iOS 26.x.
    @ViewBuilder
    func reorderContainerIfAvailable(
        _ move: @escaping (_ sources: [String], _ targetID: String?, _ collectionID: UUID) -> Void
    ) -> some View {
        if #available(iOS 27.0, *) {
            self.reorderContainer(for: WatchedStation.self, in: UUID.self) { difference in
                let targetID: String?
                switch difference.destination.position {
                case .before(let id): targetID = id
                case .end: targetID = nil
                }
                move(difference.sources, targetID, difference.destination.collectionID)
            }
        } else {
            self
        }
    }
}
