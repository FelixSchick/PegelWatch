import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            WatchlistView()
                .tabItem {
                    Label("Watchlist", systemImage: "water.waves")
                }

            StationSearchView()
                .tabItem {
                    Label("Suchen", systemImage: "magnifyingglass")
                }

            SettingsView()
                .tabItem {
                    Label("Einstellungen", systemImage: "gear")
                }
        }
    }
}
