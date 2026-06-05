import SwiftUI

struct ContentView: View {

    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @State private var store = StationStore.shared

    private var activeAlarmCount: Int {
        store.watchedStations.filter { !$0.noDataAvailable && $0.alarmLevel != .normal }.count
    }

    var body: some View {
        TabView {
            WatchlistView()
                .tabItem {
                    Label("Watchlist", systemImage: "water.waves")
                }
                .badge(activeAlarmCount)
            StationSearchView()
                .tabItem {
                    Label("Hinzufügen", systemImage: "plus.viewfinder")
                }

            SettingsView()
                .tabItem {
                    Label("Einstellungen", systemImage: "gear")
                }
        }.sheet(isPresented: .constant(!hasSeenTutorial)) {
                   TutorialView(onFinish: { hasSeenTutorial = true })
               }
    }
}
