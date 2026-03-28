import SwiftUI
import Charts

struct StationDetailView: View {

    let station: WatchedStation
    @State private var store = StationStore.shared

    // Local state for threshold editor
    @State private var showThresholdEditor = false
    @State private var thresholdInput: String = ""
    
    /// Note: Values are UP-To Values
    /// so if normal 100 every value smaller than 100 cm is normal so then 100 is warning
    @State private var showCustomThresholdEditor = false
    @State private var normalThresholdInput: Double = 100
    @State private var warningThresholdInput: Double = 200
    @State private var customThresholdValueChanged: Bool = false
    
    @State private var dangerThresholdInput: Double = 300
    
    @State private var levelHistory: [(timestamp: Date, value: Double)] = []
    @State private var isLoadingHistory = false
    @State private var historyError: String?

    // Computed live version from store
    private var liveStation: WatchedStation {
        store.watchedStations.first { $0.id == station.id } ?? station
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                levelGauge
                historyChart
                metaInfo
                alarmSection
                removeButton
            }
            .padding()
        }
        .navigationTitle(station.shortname)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
            }
        }
        .task {
            await loadHistory()
        }
        .sheet(isPresented: $showThresholdEditor) {
            thresholdSheet
        }
        .sheet(isPresented: $showCustomThresholdEditor) {
            customThresholdSheet
        }
    }

    // MARK: - Level Gauge

    private var levelGauge: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let value = liveStation.lastValue {
                    Text("\(Int(value))")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(liveStation.alarmLevel.color)
                        .contentTransition(.numericText())
                } else {
                    Text("–")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text("cm")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }

            // Alarm level badge
            Label(liveStation.alarmLevel.label, systemImage: liveStation.alarmLevel.systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(liveStation.alarmLevel.color)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(liveStation.alarmLevel.color.opacity(0.12), in: Capsule())

            // Progress bar toward threshold
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
                .padding(.top, 8)
            }

            if let updated = liveStation.lastUpdated {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("Aktualisiert \(updated, style: .relative)")
                }
                .font(.caption)
                .foregroundStyle(liveStation.isStale ? .orange : .secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    

    // MARK: - Meta Info

    private var metaInfo: some View {
        VStack(spacing: 0) {
            infoRow(label: "Gewässer", value: liveStation.waterDisplayName)
            Divider().padding(.leading)
            infoRow(label: "Behörde", value: liveStation.agency)
            if let km = liveStation.km {
                Divider().padding(.leading)
                infoRow(label: "Flusskilometer", value: String(format: "%.1f km", km))
            }
            if let lat = liveStation.latitude, let lon = liveStation.longitude {
                Divider().padding(.leading)
                infoRow(label: "Koordinaten", value: String(format: "%.4f°, %.4f°", lat, lon))
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Alarm Section

    private var alarmSection: some View {
        Section {
            VStack(spacing: 0) {
                // Alarm enable toggle
                HStack {
                    Label("Alarm aktiviert", systemImage: "bell.fill")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { liveStation.alarmEnabled },
                        set: { store.setAlarmEnabled(id: station.id, enabled: $0) }
                    ))
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading)

                // Threshold row
                Button {
                    thresholdInput = liveStation.alarmThreshold.map { String(Int($0)) } ?? ""
                    showThresholdEditor = true
                } label: {
                    HStack {
                        Label("Alarmschwelle", systemImage: "ruler")
                            .foregroundStyle(.primary)
                        Spacer()
                        if let threshold = liveStation.alarmThreshold {
                            Text("\(Int(threshold)) cm")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Nicht gesetzt")
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                
                Divider().padding(.leading)
                
                HStack {
                    Label("Eigene Warnstufen", systemImage: "gauge.open.righthalf.dotted.with.needle.and.arrow.trianglehead.backward")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { liveStation.enableCustomThreshold },
                        set: { newValue in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                store.setCustomThreshold(id: station.id, enabled: newValue)
                            }
                        }
                    ))
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                if liveStation.enableCustomThreshold {
                    
                    VStack {
                        pegelThresholdLevelButton(for: .warning)
                        pegelThresholdLevelButton(for: .critical)
                    }.onTapGesture {
                        if let value = Double(thresholdInput), value > 0 {
                                    warningThresholdInput = value
                        }
                        customThresholdValueChanged = false
                        showCustomThresholdEditor = true
                    }.transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    
                    
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
    
    private func pegelThresholdLevelButton(for alarmLevel: AlarmLevel) -> some View {
        HStack {
            if alarmLevel == .warning {
                Label("Warnschwelle", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.yellow)
                Spacer()
                if let threshold = liveStation.alarmThresholdNormalLevel {
                    Text("\(Int(threshold)) cm")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nicht gesetzt")
                        .foregroundStyle(.secondary)
                }
            } else if alarmLevel == .critical {
                Label("Kritischeschwelle", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                Spacer()
                if let threshold = liveStation.alarmThresholdDangerLevel {
                    Text("\(Int(threshold)) cm")
                        .foregroundStyle(.secondary)
        
                } else {
                    Text("Nicht gesetzt")
                        .foregroundStyle(.secondary)
                }
            }
            
            
        
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
     
    // MARK: - Remove Button

    private var removeButton: some View {
        VStack(spacing: 0) {
            Button(role: .destructive) {
                store.remove(id: station.id)
            } label: {
                Label("Station entfernen", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Threshold Sheet

    private var thresholdSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("z.B. 250", text: $thresholdInput)
                            .keyboardType(.numberPad)
                        Text("cm")
                            .foregroundStyle(.secondary)
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
                        Label("Alarmschwelle", systemImage: "ruler")
                            .foregroundStyle(.primary)
                        Spacer()
                        if let threshold = liveStation.alarmThreshold {
                            Text("\(Int(threshold)) cm")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Nicht gesetzt")
                                .foregroundStyle(.secondary)
                        }
                    
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } header: {
                    Label("Alarmschwelle", systemImage: "bell.fill")
                }
                
                Section {
                    VStack(alignment: .leading) {
                                Text("Vorwarnung ab \(Int(normalThresholdInput)) cm")
                                    .foregroundStyle(.yellow)

                                Slider(
                                    value: $normalThresholdInput,
                                    in: 0...(warningThresholdInput - 10),
                                    step: 10
                                ).onChange(of: normalThresholdInput) {
                                    customThresholdValueChanged = true
                                }
                            }
                } header: {
                    Label("Vorwarnstufenschwelle in cm", systemImage: "exclamationmark.circle")
                } footer: {
                    Text("Ab dieser Höhe wird die Vorwarnstuffe angezeigt")
                }
                
                Section {
                    VStack(alignment: .leading) {
                                Text("Kritisch ab \(Int(dangerThresholdInput)) cm")
                                    .foregroundStyle(.red)

                                Slider(
                                    value: $dangerThresholdInput,
                                    in: (warningThresholdInput+10)...(warningThresholdInput*3),
                                    step: 10
                                ).onChange(of: dangerThresholdInput) {
                                    customThresholdValueChanged = true
                                }
                    }.onTapGesture {
                        customThresholdValueChanged = true
                    }
                } header: {
                    Label("Kritischewarnstufenschwelle in cm", systemImage: "exclamationmark.circle")
                } footer: {
                    Text("Ab dieser Höhe wird die Kritikstuffe angezeigt")
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
                        
                        showCustomThresholdEditor = false
                    }.disabled(!customThresholdValueChanged)
                }
            }
        }
        .presentationDetents([.large])
    }
    
    // MARK: - History Chart
    
    private var historyChart: some View {
        LevelChartView(
                history: levelHistory,
                threshold: liveStation.alarmThreshold,
                alarmColor: liveStation.alarmLevel.color,
                liveStation: liveStation
            )
    }
    
    struct LevelChartView: View {
        let history: [(timestamp: Date, value: Double)]
        let threshold: Double?
        let alarmColor: Color
        let liveStation: WatchedStation

        @State private var selectedDate: Date? = nil
        @State private var visibleDays: Int = 7

        private var visibleHistory: [(timestamp: Date, value: Double)] {
            let cutoff = Calendar.current.date(byAdding: .day, value: -visibleDays, to: Date())!
            return history.filter { $0.timestamp >= cutoff }
        }

        private func nearest(to date: Date) -> (timestamp: Date, value: Double)? {
            visibleHistory.min(by: {
                abs($0.timestamp.timeIntervalSince(date)) <
                abs($1.timestamp.timeIntervalSince(date))
            })
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {

                // Header — shows selected value or latest
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
                } else if let latest = visibleHistory.last {
                    Text("\(Int(latest.value)) cm")
                        .font(.title.bold())
                        .foregroundStyle(alarmColor)
                    Text("Letztes Update: \(latest.timestamp.formatted(.dateTime.weekday(.wide).hour().minute().locale(Locale(identifier: "de_DE"))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Range picker
                Picker("Zeitraum", selection: $visibleDays) {
                    Text("24h").tag(1)
                    Text("7T").tag(7)
                    Text("30T").tag(30)
                }
                .pickerStyle(.segmented)
                .onChange(of: visibleDays) { selectedDate = nil }

                // Chart
                Chart {
                    ForEach(visibleHistory, id: \.timestamp) { point in
                        AreaMark(
                            x: .value("Zeit", point.timestamp),
                            y: .value("Pegel", point.value)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [alarmColor.opacity(0.3), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Zeit", point.timestamp),
                            y: .value("Pegel", point.value)
                        )
                        .foregroundStyle(alarmColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    if let threshold {
                        RuleMark(y: .value("Alarmschwelle", threshold))
                            .foregroundStyle(.red.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                    
                    if liveStation.enableCustomThreshold {
                        if liveStation.alarmThresholdNormalLevel != nil {
                            if let normalLevel = liveStation.alarmThresholdNormalLevel {
                                RuleMark(y: .value("Vorwarnstufe", normalLevel))
                                    .foregroundStyle(.yellow.opacity(0.7))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                            }
                        }
                        
                        if liveStation.alarmThresholdDangerLevel != nil {
                            if let dangerLevel = liveStation.alarmThresholdDangerLevel {
                                RuleMark(y: .value("Kritischestufe", dangerLevel))
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                        }
                    }
                    
                    

                    // Cursor
                    if let date = selectedDate, let point = nearest(to: date) {
                        RuleMark(x: .value("Auswahl", point.timestamp))
                            .foregroundStyle(.secondary.opacity(0.5))
                        PointMark(
                            x: .value("Zeit", point.timestamp),
                            y: .value("Pegel", point.value)
                        )
                        .symbolSize(80)
                        .foregroundStyle(alarmColor)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel(
                            format: visibleDays == 1
                                ? .dateTime.hour()
                                : .dateTime.month(.abbreviated).day()
                        )
                    }
                }
                .frame(height: 200)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    
    
    private func loadHistory() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            levelHistory = try await PegelOnlineAPI.shared.fetchAllLevels(for: station.id)
        } catch {
            historyError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        StationDetailView(station: .preview)
    }
}
