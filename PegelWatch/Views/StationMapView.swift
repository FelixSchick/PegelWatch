import SwiftUI
import MapKit

/// Karten-Tab: alle beobachteten Stationen mit Alarmfarbe auf einer Karte.
/// Tippen auf einen Marker öffnet die Detailansicht.
struct StationMapView: View {

    @State private var store = StationStore.shared
    @State private var selectedStation: WatchedStation?

    private var mappableStations: [WatchedStation] {
        store.watchedStations.filter { $0.latitude != nil && $0.longitude != nil }
    }

    var body: some View {
        NavigationStack {
            Map {
                ForEach(mappableStations) { station in
                    Annotation(
                        station.shortname.replacingStauAbbreviations,
                        coordinate: CLLocationCoordinate2D(
                            latitude: station.latitude ?? 0,
                            longitude: station.longitude ?? 0
                        )
                    ) {
                        marker(for: station)
                            .onTapGesture { selectedStation = station }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .navigationTitle("Karte")
            .overlay {
                if mappableStations.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Stationen", systemImage: "map")
                    } description: {
                        Text("Füge Messstationen hinzu, um sie auf der Karte zu sehen.")
                    }
                }
            }
            .sheet(item: $selectedStation) { station in
                NavigationStack {
                    StationDetailView(station: station)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Fertig") { selectedStation = nil }
                            }
                        }
                }
            }
        }
    }

    private func marker(for station: WatchedStation) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(station.alarmLevel.color.opacity(0.25))
                    .frame(width: 34, height: 34)
                Circle()
                    .fill(station.noDataAvailable ? Color.gray : station.alarmLevel.color)
                    .frame(width: 22, height: 22)
                Image(systemName: station.noDataAvailable
                      ? "antenna.radiowaves.left.and.right.slash" : "water.waves")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            if let value = station.lastValue {
                Text("\(Int(value)) cm")
                    .font(.caption2.bold().monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }
}

#Preview {
    StationMapView()
}
