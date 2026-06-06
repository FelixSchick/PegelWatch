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
        .navigationTitle(station.shortname)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.gray.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Level Gauge

    private var levelGauge: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let value = liveStation.lastValue {
                    Text("\(Int(value))")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(liveStation.alarmLevel.color)
                        .contentTransition(.numericText())
                } else {
                    Text("N/A")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if liveStation.alarmLevel.isAlarming {
                RoundedRectangle(cornerRadius: 16)
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
            Divider().padding(.leading, 44)
            infoRow(
                label: "Datenquelle",
                icon: "server.rack",
                value: HeichwaasserAPI.isLuxembourgStation(liveStation.id) ? "Héichwaasser.lu" : "PegelOnline (WSV)"
            )
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .animation(.easeInOut(duration: 0.3), value: liveStation.enableCustomThreshold)
        } header: {
            Label("Alarm", systemImage: "bell")
        } footer: {
            Text("Stelle dir eine Alarmgrenze, ab der du benachrichtigt wirst.")
        }
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
                .padding()
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.red)
        }
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
            liveStation: liveStation
        )
    }

    struct LevelChartView: View {
        let history: [(timestamp: Date, value: Double)]
        var isLoading: Bool = false
        let threshold: Double?
        let alarmColor: Color
        let liveStation: WatchedStation

        @State private var selectedDate: Date?
        @State private var visibleDays: Int = 7

        private var visibleHistory: [(timestamp: Date, value: Double)] {
            let cutoff = Calendar.current.date(byAdding: .day, value: -visibleDays, to: Date())!
            return history.filter { $0.timestamp >= cutoff }
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

        private var chartYDomain: ClosedRange<Double> {
            guard let s = stats else { return 0...100 }
            let lo = s.min
            var hi = s.max
            if let t = threshold { hi = max(hi, t) }
            let range = max(hi - lo, 1)
            let padding = max(range * 0.15, 5)
            return max(0, lo - padding)...(hi + padding)
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

                    if let threshold {
                        RuleMark(y: .value("Alarmschwelle", threshold))
                            .foregroundStyle(.red.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 3]))
                            .annotation(position: .top, alignment: .trailing) {
                                alarmLabel(text: "Alarmschwelle \(Int(threshold)) cm", color: .red)
                            }
                    }

                    if liveStation.enableCustomThreshold {
                        if let normalLevel = liveStation.alarmThresholdNormalLevel {
                            RuleMark(y: .value("Vorwarnstufe", normalLevel))
                                .foregroundStyle(.yellow.opacity(0.9))
                                .lineStyle(StrokeStyle(lineWidth: 0.75, dash: [5, 3]))
                                .annotation(position: .top, alignment: .trailing) {
                                    alarmLabel(text: "Vorwarnung \(Int(normalLevel)) cm", color: .yellow)
                                }
                        }
                        if let warningLevel = liveStation.alarmThresholdWarningLevel {
                            RuleMark(y: .value("Warnstufe", warningLevel))
                                .foregroundStyle(.orange.opacity(0.9))
                                .lineStyle(StrokeStyle(lineWidth: 0.75, dash: [5, 3]))
                                .annotation(position: .top, alignment: .trailing) {
                                    alarmLabel(text: "Warnstufe \(Int(warningLevel)) cm", color: .orange)
                                }
                        }
                        if let dangerLevel = liveStation.alarmThresholdDangerLevel {
                            RuleMark(y: .value("Gefahrenstufe", dangerLevel))
                                .foregroundStyle(.red.opacity(0.9))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                                .annotation(position: .top, alignment: .trailing) {
                                    alarmLabel(text: "Kritisch \(Int(dangerLevel)) cm", color: .red)
                                }
                        }
                    }

                    ForEach(liveStation.sortedCustomAlarms) { alarm in
                        RuleMark(y: .value(alarm.name, alarm.threshold))
                            .foregroundStyle(alarm.color.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 0.75, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                alarmLabel(text: "\(alarm.name) \(Int(alarm.threshold)) cm", color: alarm.color)
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
                .chartYScale(domain: chartYDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: visibleDays == 1 ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
                    }
                }
                .chartXSelection(value: $selectedDate)
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
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
            if HeichwaasserAPI.isLuxembourgStation(station.id) {
                levelHistory = try await HeichwaasserAPI.shared.fetchHistory(for: station.id)
            } else {
                levelHistory = try await PegelOnlineAPI.shared.fetchAllLevels(for: station.id)
            }
        } catch {
            historyError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { StationDetailView(station: .preview) }
}
