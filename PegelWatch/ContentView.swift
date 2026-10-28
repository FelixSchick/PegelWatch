import SwiftUI
import CoreSpotlight

struct ContentView: View {

    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @State private var store = StationStore.shared
    @State private var router = AppRouter.shared

    private var activeAlarmCount: Int {
        store.watchedStations.filter { !$0.noDataAvailable && $0.alarmLevel != .normal }.count
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Merkliste", systemImage: "water.waves", value: AppTab.watchlist) {
                WatchlistView()
            }
            .badge(activeAlarmCount)

            Tab("Karte", systemImage: "map", value: AppTab.map) {
                StationMapView()
            }

            Tab("Einstellungen", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }

            // Suche als eigener Such-Reiter: iOS setzt ihn als separate
            // Glas-Schaltfläche rechts neben die Tab-Leiste.
            Tab("Suchen", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                StationSearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: Binding(
            get: { !hasSeenTutorial },
            set: { if !$0 { hasSeenTutorial = true } }
        )) {
            TutorialView(onFinish: {
                hasSeenTutorial = true
                if store.watchedStations.isEmpty {
                    router.selectedTab = .search
                }
            })
        }
        // Warn-Haptik, sobald neue Alarme dazukommen
        .sensoryFeedback(trigger: activeAlarmCount) { oldCount, newCount in
            newCount > oldCount ? .warning : nil
        }
        // Spotlight-Treffer öffnet direkt die Detailansicht der Station
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
            router.selectedTab = .watchlist
            router.pendingStationID = id
        }
    }
}
