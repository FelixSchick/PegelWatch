import SwiftUI

struct ContentView: View {
    
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    
    var body: some View {
        TabView {
            WatchlistView()
                .tabItem {
                    Label("Watchlist", systemImage: "water.waves")
                }
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
