import SwiftUI
import MapKit

/// Karten-Tab: beobachtete Stationen mit Alarmfarbe, sowie beim Einzoomen
/// auch alle weiteren Messstationen zum direkten Hinzufügen.
struct StationMapView: View {

    @State private var store = StationStore.shared
    @State private var catalog = StationCatalog.shared
    @State private var selectedStation: WatchedStation?
    @State private var addCandidate: Station?
    @State private var showUnwatched = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentRegion: MKCoordinateRegion?

    // Stored so the filter runs off the main thread and doesn't block the map
    @State private var unwatchedInView: [Station] = []
    @State private var unwatchedTask: Task<Void, Never>?

    // Guidance: 0 = point to "Alle anzeigen" button, 1 = instruct to zoom & tap, 2 = done
    @AppStorage("mapGuidanceStep") private var mapGuidanceStep = 0

    /// Zoom-Schwelle: erst wenn die sichtbare Region kleiner ist als 2° in
    /// Breitengrad, werden die zusätzlichen (nicht beobachteten) Stationen
    /// eingeblendet — sonst wäre die Karte bei bundesweitem Zoom unlesbar.
    private static let unwatchedZoomThreshold: CLLocationDegrees = 2.0

    private var mappableStations: [WatchedStation] {
        store.watchedStations.filter { $0.latitude != nil && $0.longitude != nil }
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
                currentRegion = context.region
                updateUnwatchedInView()
            }
            .navigationTitle("Karte")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleUnwatched()
                    } label: {
                        Label(showUnwatched ? "Nur eigene" : "Alle anzeigen",
                              systemImage: showUnwatched ? "eye.slash" : "plus.magnifyingglass")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                // Suppress zoom hint while the guidance card already covers this instruction
                if showUnwatched, let span = currentRegion?.span,
                   span.latitudeDelta >= Self.unwatchedZoomThreshold,
                   mapGuidanceStep != 1 {
                    Text("Zoom hinein, um weitere Stationen zu sehen.")
                        .font(.footnote)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                }
                if catalog.isLoading {
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
                    // Step 1 → 2: user successfully added a station from the map
                    if mapGuidanceStep == 1 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            mapGuidanceStep = 2
                        }
                    }
                }
            }
            // Step 0 → 1: user tapped "Alle anzeigen"
            .onChange(of: showUnwatched) {
                if showUnwatched && mapGuidanceStep == 0 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        mapGuidanceStep = 1
                    }
                }
                updateUnwatchedInView()
            }
            // When catalog finishes loading, re-evaluate what's in view
            .onChange(of: catalog.stations.count) {
                updateUnwatchedInView()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if mapGuidanceStep < 2 {
                    mapGuidanceCard
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: mapGuidanceStep)
        }
    }

    // MARK: - Guidance Card

    @ViewBuilder
    private var mapGuidanceCard: some View {
        switch mapGuidanceStep {
        case 0:
            GuidanceCard(
                icon: "plus.magnifyingglass",
                iconColor: .blue,
                message: "Tippe oben rechts auf \"Alle anzeigen\", um alle 4.000 Messstationen auf der Karte zu sehen.",
                onDismiss: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        mapGuidanceStep = 2
                    }
                }
            )
        case 1:
            GuidanceCard(
                icon: "mappin.and.ellipse",
                iconColor: .teal,
                message: "Zoome in die Karte und tippe auf einen kleinen Punkt, um eine Station zur Watchlist hinzuzufügen.",
                onDismiss: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        mapGuidanceStep = 2
                    }
                }
            )
        default:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func toggleUnwatched() {
        if !showUnwatched {
            // Freeze camera before new annotations appear — MapCameraPosition.automatic
            // would re-fit the viewport to cover all of Germany when thousands of pins
            // are added, causing a dramatic zoom-out / zoom-in glitch.
            if let region = currentRegion {
                cameraPosition = .region(region)
            } else {
                // Camera hasn't fired onMapCameraChange yet; derive region from watched stations
                let lats = mappableStations.compactMap(\.latitude)
                let lons = mappableStations.compactMap(\.longitude)
                if let minLat = lats.min(), let maxLat = lats.max(),
                   let minLon = lons.min(), let maxLon = lons.max() {
                    let pad = max(2.0, max(maxLat - minLat, maxLon - minLon))
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(
                            latitude: (minLat + maxLat) / 2,
                            longitude: (minLon + maxLon) / 2
                        ),
                        span: MKCoordinateSpan(latitudeDelta: pad, longitudeDelta: pad)
                    ))
                }
            }
            catalog.loadIfNeeded()
        }
        showUnwatched.toggle()
    }

    /// Recomputes the visible unwatched station list off the main thread.
    /// Cancels any in-flight computation so rapid camera changes don't pile up.
    private func updateUnwatchedInView() {
        unwatchedTask?.cancel()

        guard showUnwatched else {
            unwatchedInView = []
            return
        }
        guard let region = currentRegion else { return }

        let span = region.span
        guard span.latitudeDelta < Self.unwatchedZoomThreshold,
              span.longitudeDelta < Self.unwatchedZoomThreshold * 2 else {
            unwatchedInView = []
            return
        }

        let latPad = span.latitudeDelta  * 0.15
        let lonPad = span.longitudeDelta * 0.15
        let minLat = region.center.latitude  - span.latitudeDelta  / 2 - latPad
        let maxLat = region.center.latitude  + span.latitudeDelta  / 2 + latPad
        let minLon = region.center.longitude - span.longitudeDelta / 2 - lonPad
        let maxLon = region.center.longitude + span.longitudeDelta / 2 + lonPad

        let watchedIDs = Set(store.watchedStations.map(\.id))
        let stations = catalog.stations

        unwatchedTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                stations.filter { st in
                    guard !watchedIDs.contains(st.uuid),
                          let lat = st.latitude, let lon = st.longitude
                    else { return false }
                    return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
                }
            }.value
            guard !Task.isCancelled else { return }
            unwatchedInView = result
        }
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
