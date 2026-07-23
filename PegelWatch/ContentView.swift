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
            WatchlistView()
                .tabItem {
                    Label("Watchlist", systemImage: "water.waves")
                }
                .badge(activeAlarmCount)
                .tag(AppTab.watchlist)

            StationMapView()
                .tabItem {
                    Label("Karte", systemImage: "map")
                }
                .tag(AppTab.map)

            StationSearchView()
                .tabItem {
                    Label("Hinzufügen", systemImage: "plus.viewfinder")
                }
                .tag(AppTab.search)

            SettingsView()
                .tabItem {
                    Label("Einstellungen", systemImage: "gear")
                }
                .tag(AppTab.settings)
        }
        .sheet(isPresented: .constant(!hasSeenTutorial)) {
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
