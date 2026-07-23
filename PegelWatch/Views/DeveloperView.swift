import SwiftUI
import TipKit

struct DeveloperView: View {
    @State private var store = StationStore.shared
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @AppStorage("searchGuidanceStep") private var searchGuidanceStep = 0
    @AppStorage("mapGuidanceStep") private var mapGuidanceStep = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Tutorial") {
                    Button("Tutorial zurücksetzen") {
                        hasSeenTutorial = false
                    }
                }

                Section("Interaktive Anleitung") {
                    Button("Suche-Anleitung zurücksetzen") {
                        searchGuidanceStep = 0
                    }
                    Button("Karten-Anleitung zurücksetzen") {
                        mapGuidanceStep = 0
                    }
                }

                Section("TipKit") {
                    Button("Alle Tips zurücksetzen") {
                        try? Tips.resetDatastore()
                        WidgetTip.hasWatchedStation = false
                    }
                }

                Section("Benachrichtigungen") {
                    Button("Test-Alarm senden") {
                        guard let station = store.watchedStations.first else { return }
                        NotificationManager.shared.sendAlarmNotification(for: station, currentValue: 2122.2)
                    }
                    .disabled(store.watchedStations.isEmpty)
                }
            }
            .navigationTitle("Developer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    DeveloperView()
}
