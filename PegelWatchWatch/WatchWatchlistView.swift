import SwiftUI

/// Root-View der Watch-App: kompakte Watchlist mit den wichtigsten Werten.
///
/// Liest die vom iPhone geschriebene Watchlist aus dem App-Group-Container.
/// Damit funktioniert die Anzeige auch ohne WatchConnectivity — solange die
/// iPhone-App mindestens einmal Daten geschrieben hat.
struct WatchWatchlistView: View {
    @State private var stations: [WatchedStation] = []
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            List {
                if stations.isEmpty {
                    ContentUnavailableView(
                        "Keine Stationen",
                        systemImage: "water.waves.slash",
                        description: Text("Füge Stationen in der iPhone-App hinzu.")
                    )
                } else {
                    ForEach(stations) { station in
                        NavigationLink(value: station.id) {
                            WatchStationRow(station: station)
                        }
                    }
                }
            }
            .navigationTitle("Pegel")
            .navigationDestination(for: String.self) { id in
                if let station = stations.first(where: { $0.id == id }) {
                    WatchStationDetailView(station: station)
                }
            }
            .refreshable { await refresh() }
        }
        .task { await load() }
    }

    private func load() {
        stations = WatchStationLoader.load()
    }

    private func refresh() async {
        isRefreshing = true
        stations = await WatchStationLoader.fetchFresh()
        isRefreshing = false
    }
}

/// Kompakte Zeile pro Station — auf der Watch zählt jedes Pixel.
struct WatchStationRow: View {
    let station: WatchedStation

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(station.alarmLevel.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(station.displayShortname)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(station.waterDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 2) {
                    Text(station.lastValue.map { "\(Int($0))" } ?? "–")
                        .font(.body.monospacedDigit().bold())
                        .foregroundStyle(station.alarmLevel.color)
                    if let trend = station.trend, abs(trend) > 0.5 {
                        Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption2.bold())
                            .foregroundStyle(trend > 0 ? .red : .green)
                    }
                }
                Text("cm")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
