import SwiftUI
import Charts

struct StationDetailView: View {

    let station: WatchedStation
    @State private var store = StationStore.shared

    @State private var showThresholdEditor = false
    @State private var thresholdInput: String = ""
    
    @Environment(\.dismiss) private var dismiss

    // Custom threshold levels — values are upper bounds (e.g. normal = value < normalLevel)
    @State private var showCustomThresholdEditor = false
    @State private var normalThresholdInput: Double = 100
    @State private var warningThresholdInput: Double = 200
    @State private var dangerThresholdInput: Double = 300
    @State private var customThresholdValueChanged = false

    @State private var levelHistory: [(timestamp: Date, value: Double)] = []
    @State private var isLoadingHistory = false
    @State private var historyError: String?

    // Charakteristische Kennwerte (MNW/MHW) — leer bei Fehler oder Luxemburg-Stationen
    @State private var characteristicValues: [String: Double] = [:]

    @State private var showHistory = false
    @State private var showAddAlarm = false
    @State private var alarmToEdit: CustomAlarm?
    @State private var glowPulse = false

    private var liveStation: WatchedStation {
        store.watchedStations.first { $0.id == station.id } ?? station
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if liveStation.noDataAvailable {
                    noDataBanner
                }
                levelGauge
                historyChart
                metaInfo
                alarmSection
                customAlarmsSection
                removeButton
            }
            .padding()
        }
        .navigationTitle(station.displayShortname)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHistory = true } label: {
                    Image(systemName: "books.vertical")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await store.refreshAll() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
            }
        }
        .task { await loadHistory() }
        // Spürbares Feedback, wenn sich die Alarmstufe der Station ändert
        .sensoryFeedback(trigger: liveStation.alarmLevel) { _, newLevel in
            newLevel.isAlarming ? .warning : .success
        }
        .sheet(isPresented: $showThresholdEditor) { thresholdSheet }
        .sheet(isPresented: $showCustomThresholdEditor) { customThresholdSheet }
        .sheet(isPresented: $showHistory) { AlarmHistoryView(station: liveStation) }
    }

    // MARK: - No Data Banner

    private var noDataBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title2)
                .foregroundStyle(.gray)
            VStack(alignment: .leading, spacing: 3) {
                Text("Keine Daten verfügbar")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text("Die API stellt für diese Messstation aktuell keine Pegeldaten bereit. Alarme sind deaktiviert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding()
        .pegelCard(tint: .gray.opacity(0.15))
    }

    // MARK: - Level Gauge

    private var levelGauge: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let value = liveStation.lastValue {
                    Text("\(Int(value))")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(liveStation.alarmLevel.color)
                        .contentTransition(.numericText())
                } else {
                    Text("N/A")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let trend = liveStation.trend, abs(trend) > 0.5 {
                        Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption.bold())
                            .foregroundStyle(trend > 0 ? .red.opacity(0.8) : .green.opacity(0.8))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text("cm")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
            }
            // VoiceOver: Zahl, Einheit und Status als ein Element vorlesen
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                liveStation.lastValue.map {
                    "Aktueller Pegelstand \(Int($0)) Zentimeter, Status \(liveStation.alarmLevel.label)"
                } ?? "Keine Daten"
            )

            HStack(spacing: 12) {
                Label(liveStation.alarmLevel.label, systemImage: liveStation.alarmLevel.systemImage)
                    .font(.caption.bold())
                    .foregroundStyle(liveStation.alarmLevel.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(liveStation.alarmLevel.color.opacity(0.12), in: Capsule())

                if let updated = liveStation.lastUpdated {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(updated, style: .relative)
                    }
                    .font(.caption2)
                    .foregroundStyle(liveStation.isStale ? .orange : .secondary)
                }
            }

            if let value = liveStation.lastValue, let threshold = liveStation.alarmThreshold {
                VStack(spacing: 4) {
                    ProgressView(value: min(value, threshold * 1.5), total: threshold * 1.5)
                        .tint(liveStation.alarmLevel.color)
                    HStack {
                        Text("0 cm")
                        Spacer()
                        Text("Schwelle: \(Int(threshold)) cm")
                            .foregroundStyle(liveStation.alarmLevel.color)
                        Spacer()
                        Text("\(Int(threshold * 1.5)) cm")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .pegelCard(tint: liveStation.alarmLevel.isAlarming
                   ? liveStation.alarmLevel.color.opacity(0.18) : nil)
        .overlay {
            if liveStation.alarmLevel.isAlarming {
                RoundedRectangle(cornerRadius: PegelDesign.cardCornerRadius)
                    .stroke(liveStation.alarmLevel.color.opacity(glowPulse ? 0.4 : 0.08), lineWidth: 1)
                    .shadow(color: liveStation.alarmLevel.color.opacity(glowPulse ? 0.3 : 0), radius: 8)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .animation(.easeInOut(duration: 0.4), value: liveStation.alarmLevel)
    }

    // MARK: - Meta Info

    private var metaInfo: some View {
        VStack(spacing: 0) {
            infoRow(label: "Gewässer", icon: "water.waves", value: liveStation.waterDisplayName)
            Divider().padding(.leading, 44)
            infoRow(label: "Behörde", icon: "building.2", value: liveStation.agency)
            if let km = liveStation.km {
                Divider().padding(.leading, 44)
                infoRow(label: "Flusskilometer", icon: "arrow.left.and.right", value: String(format: "%.1f km", km))
            }
            if let lat = liveStation.latitude, let lon = liveStation.longitude {
                Divider().padding(.leading, 44)
                infoRow(label: "Koordinaten", icon: "location", value: String(format: "%.4f°, %.4f°", lat, lon))
            }
            if let mnw = characteristicValues["MNW"] {
                Divider().padding(.leading, 44)
                infoRow(label: "MNW", icon: "arrow.down.to.line", value: "\(Int(mnw)) cm")
            }
            if let mhw = characteristicValues["MHW"] {
                Divider().padding(.leading, 44)
                infoRow(label: "MHW", icon: "arrow.up.to.line", value: "\(Int(mhw)) cm")
            }
            Divider().padding(.leading, 44)
            infoRow(
                label: "Datenquelle",
                icon: "server.rack",
                value: HeichwaasserAPI.isLuxembourgStation(liveStation.id) ? "Héichwaasser.lu" : "PegelOnline (WSV)"
            )
        }
        .pegelCard()
    }

    private func infoRow(label: String, icon: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Alarm Section

    private var alarmSection: some View {
        Section {
            VStack(spacing: 0) {
                HStack {
                    Label("Alarm aktiviert", systemImage: "bell.fill")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { liveStation.alarmEnabled },
                        set: { store.setAlarmEnabled(id: station.id, enabled: $0) }
                    ))
                    .onChange(of: liveStation.alarmEnabled) {
                        Task {
                            if liveStation.alarmEnabled {
                                await LiveActivityManager.shared.update(station: liveStation)
                            } else {
                                await LiveActivityManager.shared.end(for: liveStation)
                            }
                        }
                    }
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading)

                muteRow

                Divider().padding(.leading)

                Button {
                    thresholdInput = liveStation.alarmThreshold.map { String(Int($0)) } ?? ""
                    showThresholdEditor = true
                } label: {
                    HStack {
                        Label("Alarmschwelle", systemImage: "ruler").foregroundStyle(.primary)
                        Spacer()
                        Text(liveStation.alarmThreshold.map { "\(Int($0)) cm" } ?? "Nicht gesetzt")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .disabled(!liveStation.alarmEnabled)

                Divider().padding(.leading)

                HStack {
                    Label("Eigene Warnstufen", systemImage: "gauge.open.righthalf.dotted.with.needle.and.arrow.trianglehead.backward")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { liveStation.enableCustomThreshold },
                        set: { newValue in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                store.setCustomThreshold(id: station.id, enabled: newValue)
                                Task { await StationStore.shared.refreshAll() }
                            }
                        }
                    ))
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .disabled(!liveStation.alarmEnabled)

                if liveStation.enableCustomThreshold {
                    VStack {
                        thresholdLevelRow(for: .warning)
                        thresholdLevelRow(for: .critical)
                    }
                    .onTapGesture { openCustomThresholdEditor() }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .foregroundStyle(.primary)
                    .disabled(!liveStation.alarmEnabled)
                }
            }
            .pegelCard()
            .animation(.easeInOut(duration: 0.3), value: liveStation.enableCustomThreshold)
        } header: {
            Label("Alarm", systemImage: "bell")
        } footer: {
            Text("Stelle dir eine Alarmgrenze, ab der du benachrichtigt wirst.")
        }
    }

    /// Zeile zum vorübergehenden Stummschalten aller Mitteilungen der Station.
    /// Die gleiche Stummschaltung ist auch als Schnellaktion in der
    /// Alarm-Benachrichtigung verfügbar.
    private var muteRow: some View {
        HStack {
            if liveStation.isAlarmMuted, let until = liveStation.alarmMutedUntil {
                Label {
                    Text("Stumm bis \(until.formatted(date: .omitted, time: .shortened))")
                } icon: {
                    Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
                }
                Spacer()
                Button("Aufheben") {
                    store.unmuteAlarms(for: station.id)
                }
                .font(.subheadline)
            } else {
                Label("Vorübergehend stumm", systemImage: "bell.slash")
                Spacer()
                Menu {
                    ForEach(AlarmMuteDuration.allCases, id: \.self) { duration in
                        Button(duration.label) {
                            store.muteAlarms(for: station.id, duration: duration.seconds)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Dauer")
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .disabled(!liveStation.alarmEnabled)
    }

    private func thresholdLevelRow(for level: AlarmLevel) -> some View {
        let isWarning = level == .warning
        let label = isWarning ? "Warnschwelle" : "Kritischeschwelle"
        let color: Color = isWarning ? .yellow : .red
        let value = isWarning ? liveStation.alarmThresholdNormalLevel : liveStation.alarmThresholdDangerLevel

        return HStack {
            Label(label, systemImage: "exclamationmark.circle")
                .foregroundStyle(liveStation.alarmEnabled ? color : .white)
            Spacer()
            Text(value.map { "\(Int($0)) cm" } ?? "Nicht gesetzt").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .disabled(!liveStation.alarmEnabled)
    }

    private func openCustomThresholdEditor() {
        if let n = liveStation.alarmThresholdNormalLevel { normalThresholdInput = n }
        if let w = liveStation.alarmThresholdWarningLevel { warningThresholdInput = w }
        else if let t = liveStation.alarmThreshold, t > 0 { warningThresholdInput = t }
        if let d = liveStation.alarmThresholdDangerLevel { dangerThresholdInput = d }
        customThresholdValueChanged = false
        showCustomThresholdEditor = true
    }

    // MARK: - Remove Button

    private var removeButton: some View {
        Button(role: .destructive) {
            store.remove(id: station.id)
            dismiss()
        } label: {
            Label("Station entfernen", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .tint(.red)
    }

    // MARK: - Threshold Sheet

    private var thresholdSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("z.B. 250", text: $thresholdInput).keyboardType(.numberPad)
                        Text("cm").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Alarmschwelle in Zentimetern")
                } footer: {
                    Text("Du wirst benachrichtigt, wenn der Pegel diese Marke erreicht oder überschreitet.")
                }

                if liveStation.alarmThreshold != nil {
                    Section {
                        Button("Schwelle entfernen", role: .destructive) {
                            store.setThreshold(id: station.id, threshold: nil)
                            showThresholdEditor = false
                        }
                    }
                }
            }
            .navigationTitle("Alarmschwelle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showThresholdEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        if let value = Double(thresholdInput), value > 0 {
                            store.setThreshold(id: station.id, threshold: value)
                            Task { await StationStore.shared.refreshAll() }
                        }
                        showThresholdEditor = false
                    }
                    .disabled(thresholdInput.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Custom Threshold Sheet

    private var customThresholdSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label("Alarmschwelle", systemImage: "ruler").foregroundStyle(.primary)
                        Spacer()
                        Text(liveStation.alarmThreshold.map { "\(Int($0)) cm" } ?? "Nicht gesetzt")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } header: {
                    Label("Alarmschwelle", systemImage: "bell.fill")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Vorwarnung ab \(Int(normalThresholdInput)) cm").foregroundStyle(.yellow)
                        Slider(value: $normalThresholdInput, in: 0...(warningThresholdInput - 10), step: 10)
                            .onChange(of: normalThresholdInput) { customThresholdValueChanged = true }
                    }
                } header: {
                    Label("Vorwarnstufenschwelle in cm", systemImage: "exclamationmark.circle")
                } footer: {
                    Text("Ab dieser Höhe wird die Vorwarnstufe angezeigt")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Kritisch ab \(Int(dangerThresholdInput)) cm").foregroundStyle(.red)
                        Slider(value: $dangerThresholdInput, in: (warningThresholdInput + 10)...(warningThresholdInput * 3), step: 10)
                            .onChange(of: dangerThresholdInput) { customThresholdValueChanged = true }
                    }
                } header: {
                    Label("Kritischewarnstufenschwelle in cm", systemImage: "exclamationmark.circle")
                } footer: {
                    Text("Ab dieser Höhe wird die Kritischstufe angezeigt")
                }
            }
            .navigationTitle("Alarmschwelle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showCustomThresholdEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        store.setAlarmThresholdNormalLevel(id: liveStation.id, level: normalThresholdInput)
                        store.setAlarmThresholdDangerLevel(id: liveStation.id, level: dangerThresholdInput)
                        Task { await StationStore.shared.refreshAll() }
                        showCustomThresholdEditor = false
                    }
                    .disabled(!customThresholdValueChanged)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Custom Alarms Section

    private var customAlarmsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Eigene Alarme", systemImage: "bell.badge").font(.headline)
                Spacer()
                Button { showAddAlarm = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if liveStation.sortedCustomAlarms.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "bell.slash").font(.title2).foregroundStyle(.quaternary)
                        Text("Noch keine eigenen Alarme").font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                ForEach(liveStation.sortedCustomAlarms) { alarm in
                    Divider().padding(.leading)
                    HStack(spacing: 12) {
                        Circle().fill(alarm.color).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alarm.name).font(.subheadline.weight(.semibold))
                            Text("\(Int(alarm.threshold)) cm")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let value = liveStation.lastValue, value >= alarm.threshold {
                            Text("Aktiv")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(alarm.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(alarm.color.opacity(0.15), in: Capsule())
                        }
                        Button { alarmToEdit = alarm } label: {
                            Image(systemName: "pencil.circle").foregroundStyle(.secondary)
                        }
                        Button(role: .destructive) {
                            store.removeCustomAlarm(id: alarm.id, from: liveStation.id)
                        } label: {
                            Image(systemName: "trash.circle").foregroundStyle(.red.opacity(0.7))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
            }
        }
        .pegelCard()
        .sheet(isPresented: $showAddAlarm) {
            CustomAlarmEditorView(stationID: liveStation.id) { alarm in
                store.addCustomAlarm(alarm, to: liveStation.id)
            }
        }
        .sheet(item: $alarmToEdit) { alarm in
            CustomAlarmEditorView(stationID: liveStation.id, existing: alarm) { updated in
                store.updateCustomAlarm(updated, in: liveStation.id)
            }
        }
    }

    // MARK: - History Chart

    private var historyChart: some View {
        LevelChartView(
            history: levelHistory,
            isLoading: isLoadingHistory,
            threshold: liveStation.alarmThreshold,
            alarmColor: liveStation.alarmLevel.color,
            liveStation: liveStation,
            characteristicValues: characteristicValues
        )
    }

    struct LevelChartView: View {
        let history: [(timestamp: Date, value: Double)]
        var isLoading: Bool = false
        let threshold: Double?
        let alarmColor: Color
        let liveStation: WatchedStation
        /// MNW/MHW als dezente Kontextlinien — beeinflussen die Y-Skalierung nicht
        var characteristicValues: [String: Double] = [:]

        @State private var selectedDate: Date?
        @State private var visibleDays: Int = 7
        @State private var showAllThresholds = false

        private var visibleHistory: [(timestamp: Date, value: Double)] {
            let cutoff = Calendar.current.date(byAdding: .day, value: -visibleDays, to: Date())!
            return history.filter { $0.timestamp >= cutoff }
        }

        /// Alle Alarm-/Schwellenlinien der Station in einheitlicher Form.
        private struct AlarmLine: Identifiable {
            let id: String
            let label: String
            let value: Double
            let color: Color
            var emphasized: Bool = false
        }

        private var alarmLines: [AlarmLine] {
            var lines: [AlarmLine] = []
            if let threshold {
                lines.append(AlarmLine(id: "threshold", label: "Alarmschwelle",
                                       value: threshold, color: .red, emphasized: true))
            }
            if liveStation.enableCustomThreshold {
                if let v = liveStation.alarmThresholdNormalLevel {
                    lines.append(AlarmLine(id: "level-normal", label: "Vorwarnung", value: v, color: .yellow))
                }
                if let v = liveStation.alarmThresholdWarningLevel {
                    lines.append(AlarmLine(id: "level-warning", label: "Warnstufe", value: v, color: .orange))
                }
                if let v = liveStation.alarmThresholdDangerLevel {
                    lines.append(AlarmLine(id: "level-danger", label: "Kritisch", value: v, color: .red))
                }
            }
            for alarm in liveStation.sortedCustomAlarms {
                lines.append(AlarmLine(id: alarm.id.uuidString, label: alarm.name,
                                       value: alarm.threshold, color: alarm.color))
            }
            return lines
        }

        private var stats: (min: Double, max: Double, avg: Double)? {
            guard !visibleHistory.isEmpty else { return nil }
            let values = visibleHistory.map(\.value)
            return (
                min: values.min()!,
                max: values.max()!,
                avg: values.reduce(0, +) / Double(values.count)
            )
        }

        /// Kompromiss zwischen Verlauf und Schwellen (geteilte Logik in
        /// PegelChartScale): Weiter entfernte Schwellen erscheinen als
        /// Hinweis-Button und lassen sich vollständig einblenden.
        private var chartYDomain: ClosedRange<Double> {
            guard let s = stats else { return 0...100 }
            return PegelChartScale.domain(
                dataMin: s.min, dataMax: s.max,
                lines: alarmLines.map(\.value),
                includeAllLines: showAllThresholds
            )
        }

        private func nearest(to date: Date) -> (timestamp: Date, value: Double)? {
            visibleHistory.min {
                abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
            }
        }

        @ViewBuilder
        private func alarmLabel(text: String, color: Color) -> some View {
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                .fixedSize()
        }

        var body: some View {
            // Einmal pro Body-Auswertung berechnen — Domain/Stats sind O(n)
            // über die Historie und werden sonst beim Chart-Scrubbing
            // mehrfach pro Frame neu gerechnet.
            let domain = chartYDomain
            let visibleLines = alarmLines.filter { domain.contains($0.value) }
            let offScaleLines = alarmLines.filter { !domain.contains($0.value) }

            VStack(alignment: .leading, spacing: 12) {
                if let date = selectedDate, let point = nearest(to: date) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(point.value)) cm")
                            .font(.title.bold())
                            .foregroundStyle(alarmColor)
                            .contentTransition(.numericText())
                        Text(point.timestamp.formatted(.dateTime.weekday(.wide).hour().minute().locale(Locale(identifier: "de_DE"))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .animation(.snappy, value: point.value)
                } else if let value = liveStation.lastValue {
                    Text("\(Int(value)) cm").font(.title.bold()).foregroundStyle(alarmColor)
                    if let updated = liveStation.lastUpdated {
                        Text("Letztes Update: \(updated.formatted(.dateTime.weekday(.wide).hour().minute().locale(Locale(identifier: "de_DE"))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let latest = visibleHistory.last {
                    Text("\(Int(latest.value)) cm").font(.title.bold()).foregroundStyle(alarmColor)
                    Text("Letztes Update: \(latest.timestamp.formatted(.dateTime.weekday(.wide).hour().minute().locale(Locale(identifier: "de_DE"))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Zeitraum", selection: $visibleDays) {
                    Text("24h").tag(1)
                    Text("7T").tag(7)
                    Text("30T").tag(30)
                }
                .pickerStyle(.segmented)
                .onChange(of: visibleDays) { selectedDate = nil }

                if !offScaleLines.isEmpty || showAllThresholds {
                    Button {
                        withAnimation(.snappy) { showAllThresholds.toggle() }
                    } label: {
                        if showAllThresholds {
                            Label("Auf Verlauf zoomen", systemImage: "arrow.down.right.and.arrow.up.left")
                        } else {
                            let n = offScaleLines.count
                            Label(
                                n == 1
                                    ? "1 Schwelle außerhalb (\(Int(offScaleLines[0].value)) cm) – einblenden"
                                    : "\(n) Schwellen außerhalb – einblenden",
                                systemImage: "arrow.up.and.down.text.horizontal"
                            )
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }

                Chart {
                    ForEach(visibleHistory, id: \.timestamp) { point in
                        AreaMark(x: .value("Zeit", point.timestamp), y: .value("Pegel", point.value))
                            .foregroundStyle(.linearGradient(
                                colors: [alarmColor.opacity(0.08), alarmColor.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .interpolationMethod(.catmullRom)

                        LineMark(x: .value("Zeit", point.timestamp), y: .value("Pegel", point.value))
                            .foregroundStyle(alarmColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(by: .value("Reihe", "Wasserstand"))
                    }

                    ForEach(visibleLines) { line in
                        RuleMark(y: .value(line.label, line.value))
                            .foregroundStyle(line.color.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: line.emphasized ? 1 : 0.75, dash: [5, 3]))
                            .annotation(position: .top, alignment: .trailing) {
                                alarmLabel(text: "\(line.label) \(Int(line.value)) cm", color: line.color)
                            }
                    }

                    // Dezente Kontextlinien (MNW/MHW) — nur wenn sie in der
                    // aktuellen Y-Domain liegen; sie skalieren das Chart nicht.
                    if let mnw = characteristicValues["MNW"], domain.contains(mnw) {
                        RuleMark(y: .value("MNW", mnw))
                            .foregroundStyle(.gray.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                alarmLabel(text: "MNW", color: .gray)
                            }
                    }
                    if let mhw = characteristicValues["MHW"], domain.contains(mhw) {
                        RuleMark(y: .value("MHW", mhw))
                            .foregroundStyle(.teal.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                alarmLabel(text: "MHW", color: .teal)
                            }
                    }

                    if let date = selectedDate, let point = nearest(to: date) {
                        RuleMark(x: .value("Auswahl", point.timestamp))
                            .foregroundStyle(.secondary.opacity(0.4))
                        PointMark(x: .value("Zeit", point.timestamp), y: .value("Pegel", point.value))
                            .symbolSize(70)
                            .foregroundStyle(alarmColor)
                    }
                }
                .chartForegroundStyleScale(["Wasserstand": alarmColor])
                .chartLegend(position: .top, alignment: .leading, spacing: 8)
                .chartYScale(domain: domain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: visibleDays == 1 ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
                    }
                }
                .chartXSelection(value: $selectedDate)
                .accessibilityLabel("Pegelverlauf")
                .accessibilityHint(
                    stats.map {
                        "Minimum \(Int($0.min)) Zentimeter, Maximum \(Int($0.max)) Zentimeter im sichtbaren Zeitraum"
                    } ?? ""
                )
                .frame(height: 220)
                .overlay {
                    if isLoading {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                        ProgressView()
                    } else if visibleHistory.isEmpty && !history.isEmpty {
                        Text("Keine Daten für diesen Zeitraum")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if history.isEmpty && !isLoading {
                        VStack(spacing: 6) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.title2)
                                .foregroundStyle(.quaternary)
                            Text("Keine Verlaufsdaten")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

            if let s = stats {
                HStack(spacing: 0) {
                    statCell(label: "Min", value: "\(Int(s.min)) cm", color: .blue)
                    Divider().frame(height: 28)
                    statCell(label: "Ø", value: "\(Int(s.avg)) cm", color: .secondary)
                    Divider().frame(height: 28)
                    statCell(label: "Max", value: "\(Int(s.max)) cm", color: .red)
                }
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            }
            .padding()
            .pegelCard()
            .clipShape(RoundedRectangle(cornerRadius: PegelDesign.cardCornerRadius))
        }

        private func statCell(label: String, value: String, color: Color) -> some View {
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    private func loadHistory() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            levelHistory = try await LevelDataProvider.history(for: station.id)
            if !HeichwaasserAPI.isLuxembourgStation(station.id) {
                // MNW/MHW sind nur Kontext — Fehler still ignorieren
                characteristicValues = (try? await PegelOnlineAPI.shared.fetchCharacteristicValues(for: station.id)) ?? [:]
            }
        } catch {
            historyError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { StationDetailView(station: .preview) }
}
