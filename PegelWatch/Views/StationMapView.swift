import SwiftUI
import MapKit

/// Karten-Tab: beobachtete Stationen mit Alarmfarbe, sowie beim Einzoomen
/// auch alle weiteren Messstationen zum direkten Hinzufügen.
struct StationMapView: View {

    @State private var store = StationStore.shared
    @State private var selectedStation: WatchedStation?
    @State private var addCandidate: Station?
    @State private var allStations: [Station] = []
    @State private var isLoadingAll = false
    @State private var showUnwatched = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentSpan: MKCoordinateSpan?

    /// Zoom-Schwelle: erst wenn die sichtbare Region kleiner ist als 2° in
    /// Breitengrad, werden die zusätzlichen (nicht beobachteten) Stationen
    /// eingeblendet — sonst wäre die Karte bei bundesweitem Zoom unlesbar.
    private static let unwatchedZoomThreshold: CLLocationDegrees = 2.0

    private var mappableStations: [WatchedStation] {
        store.watchedStations.filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var unwatchedInView: [Station] {
        guard showUnwatched, let span = currentSpan else { return [] }
        let watchedIDs = Set(store.watchedStations.map(\.id))
        // Auf das aktuelle Kartenfenster begrenzen — sonst wären Deutschland
        // + Luxemburg zusammen ~500+ Marker gleichzeitig aktiv.
        let latRange = span.latitudeDelta
        let lonRange = span.longitudeDelta
        return allStations.filter { st in
            guard !watchedIDs.contains(st.id),
                  let lat = st.latitude, let lon = st.longitude
            else { return false }
            // Rohe Vorfilterung: alle mit gültigen Koordinaten im vernünftigen
            // Wertebereich — die Map selbst schneidet visuell nochmals zu.
            return lat > 0 && lon > 0 && latRange < Self.unwatchedZoomThreshold
                                     && lonRange < Self.unwatchedZoomThreshold * 2
        }
    }

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                ForEach(mappableStations) { station in
                    Annotation(
                        station.displayShortname,
                        coordinate: CLLocationCoordinate2D(
                            latitude: station.latitude ?? 0,
                            longitude: station.longitude ?? 0
                        )
                    ) {
                        watchedMarker(for: station)
                            .onTapGesture { selectedStation = station }
                            .accessibilityLabel(watchedAccessibilityLabel(for: station))
                            .accessibilityAddTraits(.isButton)
                    }
                }
                ForEach(unwatchedInView) { station in
                    Annotation(
                        station.displayShortname,
                        coordinate: CLLocationCoordinate2D(
                            latitude: station.latitude ?? 0,
                            longitude: station.longitude ?? 0
                        )
                    ) {
                        unwatchedMarker()
                            .onTapGesture { addCandidate = station }
                            .accessibilityLabel("Station \(station.displayShortname) hinzufügen")
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .onMapCameraChange(frequency: .onEnd) { context in
                currentSpan = context.region.span
            }
            .navigationTitle("Karte")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleUnwatched() }
                    } label: {
                        Label(showUnwatched ? "Nur eigene" : "Alle anzeigen",
                              systemImage: showUnwatched ? "eye.slash" : "plus.magnifyingglass")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showUnwatched, let span = currentSpan,
                   span.latitudeDelta >= Self.unwatchedZoomThreshold {
                    Text("Zoom hinein, um weitere Stationen zu sehen.")
                        .font(.footnote)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                }
                if isLoadingAll {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Lade Stationen…").font(.footnote)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                }
            }
            .overlay {
                if mappableStations.isEmpty && !showUnwatched {
                    ContentUnavailableView {
                        Label("Keine Stationen", systemImage: "map")
                    } description: {
                        Text("Füge Messstationen hinzu oder tippe oben rechts auf ‚Alle anzeigen'.")
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
            .sheet(item: $addCandidate) { candidate in
                AddStationSheet(station: candidate) {
                    store.add(WatchedStation(from: candidate))
                    addCandidate = nil
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleUnwatched() async {
        showUnwatched.toggle()
        guard showUnwatched, allStations.isEmpty else { return }
        isLoadingAll = true
        defer { isLoadingAll = false }
        async let germanFetch = PegelOnlineAPI.shared.fetchAllStations()
        async let luxFetch = HeichwaasserAPI.shared.fetchAllStations()
        var result: [Station] = (try? await germanFetch) ?? []
        if let lux = try? await luxFetch { result.append(contentsOf: lux) }
        allStations = result
    }

    // MARK: - Marker

    private func watchedMarker(for station: WatchedStation) -> some View {
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

    private func unwatchedMarker() -> some View {
        ZStack {
            Circle().fill(.thinMaterial).frame(width: 14, height: 14)
            Circle()
                .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 2)
                .frame(width: 14, height: 14)
            Image(systemName: "plus")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Color.accentColor)
        }
    }

    private func watchedAccessibilityLabel(for station: WatchedStation) -> String {
        var parts = [station.displayShortname]
        if station.noDataAvailable {
            parts.append("keine Daten")
        } else if let value = station.lastValue {
            parts.append("\(Int(value)) Zentimeter")
            parts.append(station.alarmLevel.label)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Add Sheet

private struct AddStationSheet: View {
    let station: Station
    let onAdd: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Station", value: station.displayShortname)
                    LabeledContent("Gewässer",
                                   value: station.water.longname.isEmpty
                                        ? station.water.shortname : station.water.longname)
                    if let km = station.km {
                        LabeledContent("Flusskilometer",
                                       value: String(format: "%.1f km", km))
                    }
                    LabeledContent("Behörde", value: station.agency)
                }
                Section {
                    Button {
                        onAdd()
                    } label: {
                        Label("Zur Watchlist hinzufügen", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Station hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    StationMapView()
}
