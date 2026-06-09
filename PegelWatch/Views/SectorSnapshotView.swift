import SwiftUI
import Charts

// MARK: - Builder (entry point from WatchlistView)

struct SectorSnapshotView: View {
    let allStations: [WatchedStation]

    @State private var selectedIDs: Set<String>
    @State private var timeframeDays: Int = 7
    @State private var isLoading = false
    @State private var builtSnapshot: SavedSnapshot?
    @Environment(\.dismiss) private var dismiss

    init(allStations: [WatchedStation]) {
        self.allStations = allStations
        self._selectedIDs = State(initialValue: Set(allStations.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                stationSection
                timeframeSection
            }
            .navigationTitle("Lageübersicht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { builderToolbar }
            .navigationDestination(item: $builtSnapshot) { snapshot in
                SnapshotPreviewView(snapshot: snapshot)
            }
        }
    }

    // MARK: Station section

    private var stationSection: some View {
        Section {
            ForEach(allStations) { station in
                stationRow(station)
            }
        } header: {
            HStack {
                Text("\(selectedIDs.count) von \(allStations.count) ausgewählt")
                Spacer()
                Button(selectedIDs.count == allStations.count ? "Keine" : "Alle") {
                    withAnimation {
                        selectedIDs = selectedIDs.count == allStations.count
                            ? [] : Set(allStations.map(\.id))
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.accentColor)
            }
        } footer: {
            Text("Wähle die Stationen, die in der Lageübersicht erscheinen sollen.")
        }
    }

    private func stationRow(_ station: WatchedStation) -> some View {
        let isSelected = selectedIDs.contains(station.id)
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .accentColor : Color(.tertiaryLabel))
                .font(.title3)

            Circle()
                .fill(station.noDataAvailable ? Color.gray : station.alarmLevel.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.displayName).font(.subheadline)
                Text(station.waterDisplayName).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if let value = station.lastValue {
                Text("\(Int(value)) cm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected { selectedIDs.remove(station.id) } else { selectedIDs.insert(station.id) }
            }
        }
    }

    // MARK: Timeframe section

    private var timeframeSection: some View {
        Section {
            Picker("Zeitraum", selection: $timeframeDays) {
                Text("24 Stunden").tag(1)
                Text("7 Tage").tag(7)
                Text("30 Tage").tag(30)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Zeitraum")
        } footer: {
            Text("Verlaufsdaten werden für diesen Zeitraum geladen und im Snapshot gespeichert.")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var builderToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Abbrechen") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isLoading {
                ProgressView().scaleEffect(0.8)
            } else {
                Button("Vorschau") { Task { await buildSnapshot() } }
                    .disabled(selectedIDs.isEmpty)
            }
        }
    }

    // MARK: Build snapshot

    @MainActor
    private func buildSnapshot() async {
        isLoading = true
        defer { isLoading = false }

        let selected = allStations
            .filter { selectedIDs.contains($0.id) }
            .sorted {
                let order: [AlarmLevel] = [.critical, .danger, .warning, .normal]
                let ai = order.firstIndex(of: $0.alarmLevel) ?? order.count
                let bi = order.firstIndex(of: $1.alarmLevel) ?? order.count
                return ai != bi ? ai < bi : $0.shortname < $1.shortname
            }

        let cutoff = Calendar.current.date(byAdding: .day, value: -timeframeDays, to: Date())!
        let orderedIDs = selected.map(\.id)
        var historyByID: [String: [SnapshotStationData.HistoryPoint]] = [:]

        await withTaskGroup(of: (String, [SnapshotStationData.HistoryPoint]).self) { group in
            for station in selected {
                group.addTask {
                    do {
                        let raw: [(timestamp: Date, value: Double)]
                        if HeichwaasserAPI.isLuxembourgStation(station.id) {
                            raw = try await HeichwaasserAPI.shared.fetchHistory(for: station.id)
                        } else {
                            raw = try await PegelOnlineAPI.shared.fetchAllLevels(for: station.id)
                        }
                        let pts = raw
                            .filter { $0.timestamp >= cutoff }
                            .map { SnapshotStationData.HistoryPoint(timestamp: $0.timestamp, value: $0.value) }
                        return (station.id, pts)
                    } catch {
                        return (station.id, [])
                    }
                }
            }
            for await (id, pts) in group { historyByID[id] = pts }
        }

        let stationDatas = orderedIDs.compactMap { id -> SnapshotStationData? in
            guard let station = selected.first(where: { $0.id == id }) else { return nil }
            return SnapshotStationData(from: station, history: historyByID[id] ?? [])
        }

        builtSnapshot = SavedSnapshot(
            title: "Lageübersicht · \(Date().formatted(date: .abbreviated, time: .shortened))",
            timeframeDays: timeframeDays,
            stations: stationDatas
        )
    }
}

// MARK: - Preview + Save + Share

struct SnapshotPreviewView: View {
    let snapshot: SavedSnapshot
    let isSavedAlready: Bool

    @State private var snapshotStore = SnapshotStore.shared
    @State private var pdfURL: URL?
    @State private var isSaved: Bool

    init(snapshot: SavedSnapshot, isSavedAlready: Bool = false) {
        self.snapshot = snapshot
        self.isSavedAlready = isSavedAlready
        self._isSaved = State(initialValue: isSavedAlready)
    }

    var body: some View {
        ScrollView {
            SnapshotPageView(snapshot: snapshot)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Vorschau")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { previewToolbar }
        .task { await buildPDF() }
    }

    @ToolbarContentBuilder
    private var previewToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !isSavedAlready {
                if isSaved {
                    Label("Gespeichert", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                } else {
                    Button {
                        snapshotStore.save(snapshot)
                        withAnimation { isSaved = true }
                    } label: {
                        Label("Speichern", systemImage: "square.and.arrow.down")
                    }
                }
            }

            if let url = pdfURL {
                ShareLink(
                    item: url,
                    preview: SharePreview("PegelWatch-Lageübersicht.pdf")
                ) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
            } else {
                ProgressView().scaleEffect(0.8)
            }
        }
    }

    @MainActor
    private func buildPDF() async {
        let content = SnapshotPageView(snapshot: snapshot)
            .padding(20)
            .environment(\.colorScheme, .light)
            .frame(width: 595)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 595, height: nil)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PegelWatch-Lageübersicht.pdf")

        renderer.render { size, draw in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }

        pdfURL = url
    }
}

// MARK: - Page layout (shared between on-screen preview and PDF render)

struct SnapshotPageView: View {
    let snapshot: SavedSnapshot

    private var timeframeLabel: String {
        switch snapshot.timeframeDays {
        case 1: return "24 Stunden"
        case 7: return "7 Tage"
        default: return "30 Tage"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            Rectangle().fill(Color.black).frame(height: 1.5).padding(.vertical, 14)

            summaryTable

            Rectangle().fill(Color.gray.opacity(0.25)).frame(height: 0.5).padding(.vertical, 16)

            Text("Details")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.gray)
                .padding(.bottom, 10)

            VStack(spacing: 16) {
                ForEach(snapshot.stations) { station in
                    SnapshotStationCard(station: station, timeframeDays: snapshot.timeframeDays)
                }
            }

            Spacer(minLength: 24)

            Rectangle().fill(Color.gray.opacity(0.25)).frame(height: 0.5).padding(.bottom, 8)

            footerView
        }
        .foregroundColor(.black)
        .background(Color.white)
    }

    // MARK: Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("PegelWatch")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Text("Stand: \(snapshot.createdAt.formatted(date: .numeric, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            HStack(spacing: 6) {
                Text("Lageübersicht")
                Text("·").foregroundColor(Color.gray.opacity(0.6))
                Text("\(snapshot.stations.count) Station\(snapshot.stations.count == 1 ? "" : "en")")
                Text("·").foregroundColor(Color.gray.opacity(0.6))
                Text("Zeitraum: \(timeframeLabel)")
            }
            .font(.system(size: 12))
            .foregroundColor(.gray)
        }
    }

    // MARK: Summary table

    private var summaryTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Station").frame(maxWidth: .infinity, alignment: .leading)
                Text("Pegel").frame(width: 72, alignment: .trailing)
                Text("Trend").frame(width: 38, alignment: .center)
                Text("Alarmstufe").frame(width: 82, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.gray)
            .padding(.bottom, 6)

            ForEach(Array(snapshot.stations.enumerated()), id: \.element.id) { idx, st in
                HStack(spacing: 8) {
                    Circle().fill(st.snapshotColor).frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(st.displayName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(st.waterDisplayName).font(.system(size: 9)).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Group {
                        if st.noDataAvailable { Text("—").foregroundColor(.gray) }
                        else if let v = st.lastValue { Text("\(Int(v)) cm") }
                        else { Text("—").foregroundColor(.gray) }
                    }
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .frame(width: 72, alignment: .trailing)

                    trendIcon(st).frame(width: 38, alignment: .center)

                    Text(st.noDataAvailable ? "Keine Daten" : st.alarmLevel.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(st.snapshotColor)
                        .frame(width: 82, alignment: .trailing)
                }
                .padding(.vertical, 5)
                .background(idx % 2 == 0 ? Color.clear : Color.gray.opacity(0.04))

                if idx < snapshot.stations.count - 1 {
                    Divider().background(Color.gray.opacity(0.15))
                }
            }
        }
    }

    // MARK: Footer

    private var footerView: some View {
        HStack {
            Text("Daten: pegelonline.wsv.de · heichwaasser.lu")
                .font(.system(size: 9)).foregroundColor(.gray)
            Spacer()
            Text("Erzeugt mit PegelWatch")
                .font(.system(size: 9)).foregroundColor(.gray)
        }
    }

    @ViewBuilder
    private func trendIcon(_ st: SnapshotStationData) -> some View {
        if let t = st.trend {
            Image(systemName: t > 0.5 ? "arrow.up" : t < -0.5 ? "arrow.down" : "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(
                    t > 0.5 ? Color(red: 0.85, green: 0.10, blue: 0.10)
                    : t < -0.5 ? Color(red: 0.13, green: 0.69, blue: 0.30) : .gray
                )
        } else {
            Text("—").font(.system(size: 10)).foregroundColor(.gray)
        }
    }
}

// MARK: - Station card with chart

private struct SnapshotStationCard: View {
    let station: SnapshotStationData
    let timeframeDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(station.displayName)
                        .font(.system(size: 13, weight: .bold))
                    Text(station.waterDisplayName)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if let value = station.lastValue, !station.noDataAvailable {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(value)) cm")
                                .font(.system(size: 15, weight: .bold).monospacedDigit())
                                .foregroundColor(station.snapshotColor)
                            if let t = station.trend {
                                Image(systemName: t > 0.5 ? "arrow.up" : t < -0.5 ? "arrow.down" : "arrow.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(
                                        t > 0.5 ? Color(red: 0.85, green: 0.10, blue: 0.10)
                                        : t < -0.5 ? station.snapshotColor : .gray
                                    )
                            }
                        }
                    }
                    Text(station.noDataAvailable ? "Keine Daten" : station.alarmLevel.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(station.snapshotColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(station.snapshotColor.opacity(0.12), in: Capsule())
                }
            }

            if station.noDataAvailable || station.history.isEmpty {
                HStack {
                    Spacer()
                    Text(station.noDataAvailable
                         ? "Keine Messdaten verfügbar"
                         : "Keine Verlaufsdaten für diesen Zeitraum")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                        .padding(.vertical, 16)
                    Spacer()
                }
                .background(Color.gray.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                SnapshotChartView(station: station, timeframeDays: timeframeDays)
            }
        }
        .padding(12)
        .background(station.snapshotColor.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(station.snapshotColor.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Compact chart (non-interactive)

private struct SnapshotChartView: View {
    let station: SnapshotStationData
    let timeframeDays: Int

    // Downsample to keep render fast (30-day data at 15-min intervals ≈ 2 880 pts)
    private var chartData: [SnapshotStationData.HistoryPoint] {
        let h = station.history
        guard h.count > 300 else { return h }
        let step = max(h.count / 300, 1)
        return stride(from: 0, to: h.count, by: step).map { h[$0] }
    }

    private var peak: SnapshotStationData.HistoryPoint? {
        chartData.max { $0.value < $1.value }
    }

    private var yDomain: ClosedRange<Double> {
        let values = chartData.map(\.value)
        guard !values.isEmpty else { return 0...100 }
        let lo = values.min()!
        var hi = values.max()!
        if let t = station.alarmThreshold { hi = max(hi, t) }
        let range = max(hi - lo, 1)
        // Extra top padding so peak annotation doesn't clip
        let pad = max(range * 0.22, 8)
        return max(0, lo - pad * 0.5)...(hi + pad)
    }

    private var de: Locale { Locale(identifier: "de_DE") }

    private func peakTimestamp(_ date: Date) -> String {
        switch timeframeDays {
        case 1:  return date.formatted(.dateTime.hour().minute().locale(de))
        case 7:  return date.formatted(.dateTime.weekday(.wide).hour().minute().locale(de))
        default: return date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(de))
        }
    }

    var body: some View {
        Chart {
            ForEach(chartData, id: \.timestamp) { pt in
                AreaMark(
                    x: .value("Zeit", pt.timestamp),
                    y: .value("Pegel", pt.value)
                )
                .foregroundStyle(.linearGradient(
                    colors: [station.snapshotColor.opacity(0.12), station.snapshotColor.opacity(0.01)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Zeit", pt.timestamp),
                    y: .value("Pegel", pt.value)
                )
                .foregroundStyle(station.snapshotColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            // Alarm threshold
            if let threshold = station.alarmThreshold {
                RuleMark(y: .value("Schwelle", threshold))
                    .foregroundStyle(Color(red: 0.85, green: 0.10, blue: 0.10).opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Schwelle \(Int(threshold)) cm")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Color(red: 0.85, green: 0.10, blue: 0.10))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color(red: 0.85, green: 0.10, blue: 0.10).opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
            }

            // Peak marker
            if let peak {
                // Vertical guide to peak
                RuleMark(x: .value("Peak", peak.timestamp))
                    .foregroundStyle(Color.orange.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // Peak point + callout
                PointMark(
                    x: .value("Zeit", peak.timestamp),
                    y: .value("Pegel", peak.value)
                )
                .symbolSize(40)
                .foregroundStyle(Color.orange)
                .annotation(position: .top, alignment: .center, spacing: 3) {
                    VStack(spacing: 1) {
                        Text("▲ \(Int(peak.value)) cm")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(red: 0.85, green: 0.45, blue: 0.00))
                        Text(peakTimestamp(peak.timestamp))
                            .font(.system(size: 7))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
                    )
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.gray.opacity(0.15))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
                            .font(.system(size: 8))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: xAxisTickCount)) { value in
                AxisGridLine().foregroundStyle(Color.gray.opacity(0.15))
                AxisTick().foregroundStyle(Color.gray.opacity(0.4))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xLabel(for: date))
                            .font(.system(size: 8))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .frame(height: 120)
    }

    private var xAxisTickCount: Int {
        switch timeframeDays {
        case 1:  return 6   // every ~4 h
        case 7:  return 7   // one per day
        default: return 5   // ~weekly marks
        }
    }

    private func xLabel(for date: Date) -> String {
        switch timeframeDays {
        case 1:  return date.formatted(.dateTime.hour().minute().locale(de))
        case 7:  return date.formatted(.dateTime.weekday(.abbreviated).locale(de))
        default: return date.formatted(.dateTime.day().month(.abbreviated).locale(de))
        }
    }
}

// MARK: - Previews

#Preview("Builder") {
    SectorSnapshotView(allStations: [.preview, .previewAlarming, .previewNoData])
}

#Preview("Preview view") {
    NavigationStack {
        SnapshotPreviewView(snapshot: SavedSnapshot(
            title: "Lageübersicht · 09.06.2026",
            timeframeDays: 7,
            stations: [
                SnapshotStationData(from: .preview, history: []),
                SnapshotStationData(from: .previewAlarming, history: []),
            ]
        ))
    }
}
