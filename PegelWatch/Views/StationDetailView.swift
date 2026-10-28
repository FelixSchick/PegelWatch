import SwiftUI
import Charts
import Accessibility
import TipKit
import UserNotifications

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
    @State private var showRemoveConfirm = false
    @State private var alarmCreationTip = AlarmCreationTip()
    @State private var notificationStatus: UNAuthorizationStatus?
    @Environment(\.scenePhase) private var scenePhase
    /// Pegel-Ziffer wächst mit Dynamic Type mit, damit die Hierarchie erhalten bleibt.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 64

    private var liveStation: WatchedStation {
        store.watchedStations.first { $0.id == station.id } ?? station
    }

    var body: some View {
        List {
            if let error = store.lastError {
                Section {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if liveStation.noDataAvailable {
                Section { noDataBanner }
            } else if liveStation.isStale && liveStation.lastValue != nil {
                Section { staleBanner }
                    .listRowBackground(tintedRowBackground(.orange.opacity(0.12)))
            }
            Section { levelGauge }
                .listRowBackground(tintedRowBackground(
                    liveStation.alarmLevel.isAlarming ? liveStation.alarmLevel.color.opacity(0.12) : nil
                ))
            // Kein Wegklicken: Solange der Alarm an ist, aber keine Schwelle existiert,
            // ist der Hinweis wahr. Wer nur beobachten will, schaltet den Alarm aus.
            if liveStation.alarmEnabled && liveStation.alarmThreshold == nil
                    && !liveStation.noDataAvailable && liveStation.lastValue != nil {
                Section { thresholdGuidanceRow }
            }
            Section { historyChart }
            alarmSection
            customAlarmsSection
            metaInfo
            removeSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(station.displayShortname)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            async let values: Void = store.refreshAll()
            async let history: Void = loadHistory()
            _ = await (values, history)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHistory = true } label: {
                    Label("Alarmverlauf", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
            }
        }
        .task { await loadHistory() }
        .task(id: scenePhase) {
            // Neu prüfen, wenn man aus den iOS-Einstellungen zurückkommt
            if scenePhase == .active {
                notificationStatus = await NotificationManager.shared.authorizationStatus
            }
        }
        // Spürbares Feedback, wenn sich die Alarmstufe der Station ändert
        .sensoryFeedback(trigger: liveStation.alarmLevel) { oldLevel, newLevel in
            // Neue Alarme (Normal → Stufe) meldet ContentView bereits; hier nur
            // Steigerungen innerhalb der Alarmstufen und die Entwarnung.
            if newLevel == .normal { return oldLevel == .normal ? nil : .success }
            return oldLevel != .normal && newLevel.severity > oldLevel.severity ? .warning : nil
        }
        .sheet(isPresented: $showThresholdEditor) { thresholdSheet }
        .sheet(isPresented: $showCustomThresholdEditor) { customThresholdSheet }
        .sheet(isPresented: $showHistory) { AlarmHistoryView(station: liveStation) }
        .sheet(isPresented: $showAddAlarm) {
            CustomAlarmEditorView(stationID: liveStation.id) { alarm in
                store.addCustomAlarm(alarm, to: liveStation.id)
            }
        }
        .sheet(item: $alarmToEdit) { alarm in
            CustomAlarmEditorView(stationID: liveStation.id, existing: alarm) { updated in
                store.updateCustomAlarm(updated, in: liveStation.id)
            } onDelete: {
                store.removeCustomAlarm(id: alarm.id, from: liveStation.id)
            }
        }
        .confirmationDialog(
            "\(station.displayShortname) entfernen?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Station entfernen", role: .destructive) {
                store.remove(id: station.id)
                dismiss()
            }
        } message: {
            Text("Alarmschwellen und eigene Alarme dieser Station werden gelöscht.")
        }
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
        .padding(.vertical, 4)
    }

    /// Zeilenhintergrund der Liste, optional mit Farbton (Alarm, veraltete Daten).
    private func tintedRowBackground(_ tint: Color?) -> some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)
            if let tint { tint }
        }
    }

    // MARK: - Stale Banner

    private var staleBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Daten veraltet")
                    .font(.subheadline.bold())
                if let updated = liveStation.lastUpdated {
                    
                    Text("Letzter Messwert vom \(updated.formatted()). Der Sensor meldet sich möglicherweise nicht.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                Task { await store.refreshAll() }
            } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(store.isRefreshing)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Threshold Guidance

    /// Inline-Hinweis statt schwebender Karte: öffnet direkt den Schwellen-Editor.
    private var thresholdGuidanceRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                thresholdInput = ""
                showThresholdEditor = true
            } label: {
                Label {
                    Text("Setze eine Alarmschwelle, damit du bei erhöhtem Pegel benachrichtigt wirst.")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "ruler").foregroundStyle(.orange)
                }
                .font(.subheadline)
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Level Context

    private func levelContextLabel(value: Double, mnw: Double, mhw: Double) -> String {
        guard mhw > mnw else { return "" }
        if value < mnw { return "Unter MNW" }
        if value > mhw { return "Über MHW" }
        let fraction = (value - mnw) / (mhw - mnw)
        switch fraction {
        case ..<0.25: return "Niedrigwasser"
        case 0.25..<0.5: return "Unter Mittelwert"
        case 0.5..<0.75: return "Über Mittelwert"
        default: return "Erhöhter Pegel"
        }
    }

    // MARK: - Level Gauge

    private var levelGauge: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let value = liveStation.lastValue {
                    Text("\(Int(value))")
                        .font(.system(size: heroSize, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        // Alarmfarbe tragen Kartenhintergrund, Rand und Status-Kapsel;
                        // Orange erreicht als Textfarbe nur ~2,3:1.
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                } else {
                    Text("–")
                        .font(.system(size: heroSize, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Text("cm")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            // VoiceOver: Zahl, Einheit und Status als ein Element vorlesen
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                liveStation.lastValue.map {
                    "Aktueller Pegelstand \(Int($0)) Zentimeter, Status \(liveStation.alarmLevel.label)"
                } ?? "Keine Daten"
            )

            HStack(spacing: 8) {
                Label {
                    Text(liveStation.alarmLevel.label)
                } icon: {
                    Image(systemName: liveStation.alarmLevel.systemImage)
                        .foregroundStyle(liveStation.alarmLevel.color)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(liveStation.alarmLevel.color.opacity(0.18), in: Capsule())

                if let rate = liveStation.riseRateCmPerHour, abs(rate) >= 0.5 {
                    Label(String(format: "%+.1f cm/h", rate),
                          systemImage: rate > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.fill.tertiary, in: Capsule())
                }
            }

            if let updated = liveStation.lastUpdated {
                RelativeTimeText(date: updated, prefix: "Gemessen ")
                    .font(.footnote)
                    .foregroundStyle(liveStation.isStale ? .orange : .secondary)
            }

            if let value = liveStation.lastValue, let threshold = liveStation.alarmThreshold {
                VStack(spacing: 4) {
                    ProgressView(value: min(value, threshold * 1.5), total: threshold * 1.5)
                        .tint(liveStation.alarmLevel.color)
                    HStack {
                        Text("0 cm")
                        Spacer()
                        Text("Schwelle: \(Int(threshold)) cm")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(Int(threshold * 1.5)) cm")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            if let mnw = characteristicValues["MNW"],
               let mhw = characteristicValues["MHW"],
               let value = liveStation.lastValue,
               mhw > mnw {
                let fraction = min(max((value - mnw) / (mhw - mnw), 0), 1)
                VStack(spacing: 4) {
                    ProgressView(value: fraction)
                        .tint(liveStation.alarmLevel.color)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("MNW").font(.caption2)
                            Text("\(Int(mnw)) cm").font(.caption2.monospacedDigit())
                        }
                        .foregroundStyle(.secondary)
                        Spacer()
                        // Kein Alarmfarbton: „Über MHW“ in Grün wäre ein Widerspruch
                        Text(levelContextLabel(value: value, mnw: mnw, mhw: mhw))
                            .font(.caption2.bold())
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("MHW").font(.caption2)
                            Text("\(Int(mhw)) cm").font(.caption2.monospacedDigit())
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.4), value: liveStation.alarmLevel)
    }

    // MARK: - Meta Info

    private var metaInfo: some View {
        Section("Station") {
            infoRow(label: "Gewässer", icon: "water.waves", value: liveStation.waterDisplayName)
            infoRow(label: "Behörde", icon: "building.2", value: liveStation.agency)
            if let km = liveStation.km {
                infoRow(label: "Flusskilometer", icon: "arrow.left.and.right", value: String(format: "%.1f km", km))
            }
            if let lat = liveStation.latitude, let lon = liveStation.longitude {
                infoRow(label: "Koordinaten", icon: "location", value: String(format: "%.4f°, %.4f°", lat, lon))
            }
            if let mnw = characteristicValues["MNW"] {
                infoRow(label: "MNW", icon: "arrow.down.to.line", value: "\(Int(mnw)) cm")
            }
            if let mhw = characteristicValues["MHW"] {
                infoRow(label: "MHW", icon: "arrow.up.to.line", value: "\(Int(mhw)) cm")
            }
            infoRow(
                label: "Datenquelle",
                icon: "server.rack",
                value: HeichwaasserAPI.isLuxembourgStation(liveStation.id) ? "Héichwaasser.lu" : "PegelOnline (WSV)"
            )
        }
    }

    /// `LabeledContent` stapelt Titel und Wert bei großen Schriftgrößen selbst.
    private func infoRow(label: String, icon: String, value: String) -> some View {
        LabeledContent {
            Text(value)
        } label: {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Alarm Section

    private var alarmSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { liveStation.alarmEnabled },
                set: { store.setAlarmEnabled(id: station.id, enabled: $0) }
            )) {
                Label("Alarm", systemImage: "bell.fill")
            }
            .onChange(of: liveStation.alarmEnabled) {
                Task {
                    if liveStation.alarmEnabled {
                        await LiveActivityManager.shared.update(station: liveStation)
                    } else {
                        await LiveActivityManager.shared.end(for: liveStation)
                    }
                }
            }

            muteRow

            Button {
                thresholdInput = liveStation.alarmThreshold.map { String(Int($0)) } ?? ""
                showThresholdEditor = true
            } label: {
                sheetRowLabel(
                    Label("Alarmschwelle", systemImage: "ruler"),
                    value: liveStation.alarmThreshold.map { "\(Int($0)) cm" } ?? "Nicht gesetzt"
                )
            }
            .disabled(!liveStation.alarmEnabled)

            Toggle(isOn: Binding(
                get: { liveStation.enableCustomThreshold },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        store.setCustomThreshold(id: station.id, enabled: newValue)
                        Task { await StationStore.shared.refreshAll() }
                    }
                }
            )) {
                Label("Eigene Warnstufen", systemImage: "gauge.open.righthalf.dotted.with.needle.and.arrow.trianglehead.backward")
            }
            .disabled(!liveStation.alarmEnabled)

            if liveStation.enableCustomThreshold {
                thresholdLevelRow(for: .warning)
                thresholdLevelRow(for: .critical)
            }

            if liveStation.alarmEnabled && notificationStatus == .denied {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Mitteilungen in Einstellungen erlauben", systemImage: "gear")
                }
            }
        } header: {
            Text("Benachrichtigungen")
        } footer: {
            Text(alarmFooter)
        }
    }

    /// Sagt ehrlich, ob ein Alarm die Person tatsächlich erreichen kann.
    private var alarmFooter: String {
        if !liveStation.alarmEnabled {
            return "Aktiviere den Alarm, um Schwellen festzulegen."
        }
        if notificationStatus == .denied {
            return "Mitteilungen für PegelWatch sind ausgeschaltet – Alarme können dich nicht erreichen."
        }
        if liveStation.alarmThreshold == nil {
            return "Noch keine Alarmschwelle – du wirst nicht benachrichtigt."
        }
        return "Du wirst benachrichtigt, sobald der Pegel die Alarmschwelle erreicht."
    }

    /// Zeile, die ein Bearbeitungs-Sheet öffnet: Titel, Wert und Chevron.
    /// Explizite Farben, weil Button-Labels sonst in der Tint-Farbe erscheinen
    /// und `.disabled` sie nicht mehr abdunkeln würde.
    private func sheetRowLabel(_ label: some View, value: String) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text(value)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        } label: {
            label
        }
        .foregroundStyle(liveStation.alarmEnabled ? Color.primary : Color.secondary)
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
                .buttonStyle(.borderless)
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
                        Text("Stummschalten")
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
            }
        }
        .disabled(!liveStation.alarmEnabled)
    }

    private func thresholdLevelRow(for level: AlarmLevel) -> some View {
        let isWarning = level == .warning
        let value = isWarning ? liveStation.alarmThresholdNormalLevel : liveStation.alarmThresholdDangerLevel

        return Button { openCustomThresholdEditor() } label: {
            sheetRowLabel(
                Label {
                    Text(isWarning ? "Vorwarnung" : "Kritisch")
                } icon: {
                    Image(systemName: level.systemImage)
                        .foregroundStyle(liveStation.alarmEnabled ? level.color : .secondary)
                },
                value: value.map { "\(Int($0)) cm" } ?? "Nicht gesetzt"
            )
        }
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

    private var removeSection: some View {
        Section {
            Button("Station entfernen", role: .destructive) {
                showRemoveConfirm = true
            }
            .frame(maxWidth: .infinity)
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

                let mhw = characteristicValues["MHW"]
                let mnw = characteristicValues["MNW"]
                if mhw != nil || mnw != nil {
                    Section {
                        if let mhw {
                            Button {
                                thresholdInput = String(Int(mhw))
                            } label: {
                                HStack {
                                    Text("MHW – Mittleres Hochwasser")
                                    Spacer()
                                    Text("\(Int(mhw)) cm").foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let mhw, let mnw {
                            Button {
                                thresholdInput = String(Int(mnw + (mhw - mnw) * 0.8))
                            } label: {
                                HStack {
                                    Text("80 % Richtung MHW")
                                    Spacer()
                                    Text("\(Int(mnw + (mhw - mnw) * 0.8)) cm").foregroundStyle(.secondary)
                                }
                            }
                            Button {
                                thresholdInput = String(Int((mnw + mhw) / 2))
                            } label: {
                                HStack {
                                    Text("Mittelwert (MNW+MHW)/2")
                                    Spacer()
                                    Text("\(Int((mnw + mhw) / 2)) cm").foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Vorschläge")
                    } footer: {
                        Text("MNW/MHW sind charakteristische Kennwerte dieser Station.")
                    }
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
                    // Ungültige Eingaben nicht stillschweigend verwerfen
                    .disabled((Double(thresholdInput) ?? 0) <= 0)
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
                        Text("Vorwarnung ab \(Int(normalThresholdInput)) cm")
                        Slider(value: $normalThresholdInput, in: 0...(warningThresholdInput - 10), step: 10) {
                            Text("Vorwarnung")
                        }
                        .accessibilityValue("\(Int(normalThresholdInput)) Zentimeter")
                            .onChange(of: normalThresholdInput) { customThresholdValueChanged = true }
                    }
                } header: {
                    Label("Vorwarnung", systemImage: AlarmLevel.warning.systemImage)
                } footer: {
                    Text("Ab dieser Höhe wird die Vorwarnstufe angezeigt")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Kritisch ab \(Int(dangerThresholdInput)) cm")
                        Slider(value: $dangerThresholdInput, in: (warningThresholdInput + 10)...(warningThresholdInput * 3), step: 10) {
                            Text("Kritisch")
                        }
                        .accessibilityValue("\(Int(dangerThresholdInput)) Zentimeter")
                            .onChange(of: dangerThresholdInput) { customThresholdValueChanged = true }
                    }
                } header: {
                    Label("Kritisch", systemImage: AlarmLevel.critical.systemImage)
                } footer: {
                    Text("Ab dieser Höhe wird die Stufe „Kritisch“ angezeigt")
                }
            }
            .navigationTitle("Eigene Warnstufen")
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
        Section("Eigene Alarme") {
            if liveStation.sortedCustomAlarms.isEmpty {
                TipView(alarmCreationTip)
                    .tipBackground(Color.clear)
            } else {
                ForEach(liveStation.sortedCustomAlarms) { alarm in
                    Button { alarmToEdit = alarm } label: {
                        customAlarmRow(alarm)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.removeCustomAlarm(id: alarm.id, from: liveStation.id)
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button { alarmToEdit = alarm } label: {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            store.removeCustomAlarm(id: alarm.id, from: liveStation.id)
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            }

            Button { showAddAlarm = true } label: {
                Label("Alarm hinzufügen", systemImage: "plus.circle.fill")
            }
        }
    }

    private func customAlarmRow(_ alarm: CustomAlarm) -> some View {
        let isActive = liveStation.lastValue.map { $0 >= alarm.threshold } ?? false
        return HStack(spacing: 12) {
            Image(systemName: isActive ? "bell.badge.fill" : "bell.fill")
                .foregroundStyle(alarm.color)
            Text(alarm.name)
                .foregroundStyle(.primary)
            Spacer()
            if isActive {
                Text("Aktiv")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(alarm.color.opacity(0.22), in: Capsule())
            }
            Text("\(Int(alarm.threshold)) cm")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Zum Bearbeiten doppeltippen")
    }

    // MARK: - History Chart

    private var historyChart: some View {
        LevelChartView(
            history: levelHistory,
            isLoading: isLoadingHistory,
            errorMessage: historyError,
            onRetry: { Task { await loadHistory() } },
            threshold: liveStation.alarmThreshold,
            alarmColor: liveStation.alarmLevel.color,
            liveStation: liveStation,
            characteristicValues: characteristicValues
        )
    }

    struct LevelChartView: View {
        let history: [(timestamp: Date, value: Double)]
        var isLoading: Bool = false
        var errorMessage: String?
        var onRetry: (() -> Void)?
        let threshold: Double?
        let alarmColor: Color
        let liveStation: WatchedStation
        /// MNW/MHW als dezente Kontextlinien — beeinflussen die Y-Skalierung nicht
        var characteristicValues: [String: Double] = [:]

        @State private var selectedDate: Date?
        @State private var visibleDays: Int = 7
        @State private var showAllThresholds = false
        @State private var showForecast: Bool = true

        /// 3h-Prognose auf Basis der letzten 6h. Nur bei 24h-Ansicht sinnvoll,
        /// bei größeren Zeiträumen verschwindet der schmale Prognose-Kegel.
        private var forecast: LevelForecast.Result? {
            guard visibleDays == 1 else { return nil }
            return LevelForecast.forecast(history: history)
        }

        private var visibleHistory: [(timestamp: Date, value: Double)] {
            let cutoff = Calendar.current.date(byAdding: .day, value: -visibleDays, to: Date())!
            let filtered = history.filter { $0.timestamp >= cutoff }
            // Wenn die Station seit länger als `visibleDays` keine neuen Werte mehr
            // geliefert hat, zeigen wir die letzten bekannten Werte statt eines
            // leeren Charts.
            return filtered.isEmpty ? history : filtered
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
                                       value: threshold, color: AlarmLevel.danger.color, emphasized: true))
            }
            if liveStation.enableCustomThreshold {
                if let v = liveStation.alarmThresholdNormalLevel {
                    lines.append(AlarmLine(id: "level-normal", label: "Vorwarnung", value: v, color: AlarmLevel.warning.color))
                }
                if let v = liveStation.alarmThresholdWarningLevel {
                    lines.append(AlarmLine(id: "level-warning", label: "Warnstufe", value: v, color: AlarmLevel.danger.color))
                }
                if let v = liveStation.alarmThresholdDangerLevel {
                    lines.append(AlarmLine(id: "level-danger", label: "Kritisch", value: v, color: AlarmLevel.critical.color))
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
            // Farbe nur im Hintergrund: Gelb/Orange als Textfarbe wären unlesbar
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
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
                // Beim Scrubben zeigt der Kopf den gewählten Messwert; sonst nur
                // den Titel – der aktuelle Pegel steht bereits groß darüber.
                VStack(alignment: .leading, spacing: 2) {
                    if let date = selectedDate, let point = nearest(to: date) {
                        Text("\(Int(point.value)) cm")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText())
                        Text(point.timestamp.formatted(.dateTime.weekday(.wide).hour().minute().locale(Locale(identifier: "de_DE"))))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Verlauf")
                            .font(.title3.weight(.semibold))
                        Text("Gedrückt halten und ziehen für Einzelwerte")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .animation(.snappy, value: selectedDate)
                .accessibilityAddTraits(.isHeader)

                Picker("Zeitraum", selection: $visibleDays) {
                    Text("24h").tag(1)
                    Text("7 Tage").tag(7)
                    Text("30 Tage").tag(30)
                }
                .pickerStyle(.segmented)
                .onChange(of: visibleDays) { selectedDate = nil }

                if let forecast, visibleDays == 1 {
                    forecastSummary(forecast)
                }

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
                    .buttonStyle(.bordered)
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

                    // Prognose — nur 24h-Ansicht, dezent gestrichelt in Alarmfarbe.
                    if showForecast, let forecast, visibleDays == 1 {
                        ForEach(forecast.confidence, id: \.timestamp) { band in
                            AreaMark(
                                x: .value("Zeit", band.timestamp),
                                yStart: .value("Unten", band.lower),
                                yEnd:   .value("Oben",  band.upper)
                            )
                            .foregroundStyle(alarmColor.opacity(0.12))
                            .interpolationMethod(.catmullRom)
                        }
                        ForEach(forecast.projected, id: \.timestamp) { p in
                            LineMark(
                                x: .value("Zeit", p.timestamp),
                                y: .value("Pegel", p.value)
                            )
                            .foregroundStyle(alarmColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(by: .value("Reihe", "Prognose"))
                        }
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
                .chartForegroundStyleScale([
                    "Wasserstand": alarmColor,
                    "Prognose": alarmColor.opacity(0.6)
                ])
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
                .accessibilityChartDescriptor(
                    LevelChartAXDescriptor(
                        stationName: liveStation.displayName,
                        water: liveStation.waterDisplayName,
                        threshold: threshold,
                        history: visibleHistory,
                        stats: stats
                    )
                )
                .frame(height: 220)
                .overlay {
                    if isLoading {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                        ProgressView()
                    } else if visibleHistory.isEmpty && !history.isEmpty {
                        VStack(spacing: 4) {
                            Text("Keine Daten für diesen Zeitraum")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let lastUpdate = history.last?.timestamp {
                                Text("Letzte Messung: \(lastUpdate.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier: "de_DE"))))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if history.isEmpty, errorMessage != nil {
                        // Ladefehler nicht als „keine Daten“ tarnen
                        VStack(spacing: 8) {
                            Label("Verlauf konnte nicht geladen werden", systemImage: "wifi.exclamationmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Erneut laden") { onRetry?() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    } else if history.isEmpty && !isLoading {
                        VStack(spacing: 6) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.title2)
                                .foregroundStyle(.quaternary)
                            Text("Keine Verlaufsdaten")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            if let s = stats {
                HStack(spacing: 0) {
                    statCell(label: "Min", value: "\(Int(s.min)) cm")
                    Divider().frame(height: 28)
                    statCell(label: "Ø", value: "\(Int(s.avg)) cm")
                    Divider().frame(height: 28)
                    statCell(label: "Max", value: "\(Int(s.max)) cm")
                }
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            }
            .padding(.vertical, 8)
        }

        /// Kompakte Zusammenfassung der 3h-Prognose mit Toggle.
        /// Ohne aussagekräftiges R² (< 0.2) wird nur ein Hinweis angezeigt.
        @ViewBuilder
        private func forecastSummary(_ forecast: LevelForecast.Result) -> some View {
            let hoursAhead = 3.0
            let projected = forecast.value(hoursAhead: hoursAhead)
            let delta = projected.map { $0 - (history.last?.value ?? $0) } ?? 0
            let reliable = forecast.rSquared >= 0.2

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if reliable, let projected {
                        Text("Prognose in 3 Std.: \(Int(projected)) cm (\(delta >= 0 ? "+" : "")\(Int(delta)))")
                            .font(.caption.weight(.semibold).monospacedDigit())
                        // Hinweis gut lesbar halten: verhindert, dass die Schätzung
                        // mit einer amtlichen Hochwasservorhersage verwechselt wird.
                        Text("Mathematische Schätzung aus den letzten 6 Stunden (Trend \(String(format: "%+.1f", forecast.slopePerHour)) cm/h), keine offizielle Vorhersage.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Prognose zu unsicher")
                            .font(.caption.weight(.semibold))
                        Text("Die letzten 6 Stunden zeigen keinen klaren Trend.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                // Außerhalb einer Liste: Umschalt-Button statt Schalter (HIG Toggles)
                Toggle("Prognose im Diagramm", systemImage: "chart.line.uptrend.xyaxis", isOn: $showForecast)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(alarmColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }

        private func statCell(label: String, value: String) -> some View {
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.monospacedDigit().bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    private func loadHistory() async {
        isLoadingHistory = true
        historyError = nil
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
    NavigationStack { StationDetailView(station: .previewOldData) }
}

// MARK: - Accessibility Chart Descriptor

/// Beschreibt das Pegel-Chart für VoiceOver AudioGraphs. Nutzer können damit
/// den Verlauf als Tonhöhen-Verlauf abspielen und mit Rotor durch Datenpunkte
/// navigieren.
private struct LevelChartAXDescriptor: AXChartDescriptorRepresentable {
    let stationName: String
    let water: String
    let threshold: Double?
    let history: [(timestamp: Date, value: Double)]
    let stats: (min: Double, max: Double, avg: Double)?

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = history.map(\.value)
        let yMin = values.min() ?? 0
        let yMax = values.max() ?? 100
        let yPadding = max((yMax - yMin) * 0.1, 5)

        let xLower = history.first?.timestamp.timeIntervalSince1970 ?? 0
        let xUpper = history.last?.timestamp.timeIntervalSince1970 ?? (xLower + 1)

        let xAxis = AXNumericDataAxisDescriptor(
            __title: "Zeit",
            lowerBound: xLower,
            upperBound: xUpper,
            gridlinePositions: []
        ) { value in
            Date(timeIntervalSince1970: value)
                .formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(Locale(identifier: "de_DE")))
        }

        let yAxis = AXNumericDataAxisDescriptor(
            __title: "Pegel in Zentimetern",
            lowerBound: max(0, yMin - yPadding),
            upperBound: yMax + yPadding,
            gridlinePositions: []
        ) { value in
            "\(Int(value)) Zentimeter"
        }

        let points = history.map {
            AXDataPoint(x: $0.timestamp.timeIntervalSince1970, y: $0.value)
        }

        let series = AXDataSeriesDescriptor(
            name: "Wasserstand",
            isContinuous: true,
            dataPoints: points
        )

        var summaryParts: [String] = []
        summaryParts.append("Pegel \(stationName) am \(water)")
        if let stats {
            summaryParts.append("Minimum \(Int(stats.min)), Durchschnitt \(Int(stats.avg)), Maximum \(Int(stats.max)) Zentimeter")
        }
        if let threshold {
            summaryParts.append("Alarmschwelle bei \(Int(threshold)) Zentimetern")
            if let last = history.last?.value {
                summaryParts.append(last >= threshold
                    ? "Der aktuelle Wert liegt über der Schwelle"
                    : "Der aktuelle Wert liegt unter der Schwelle")
            }
        }

        return AXChartDescriptor(
            title: "Pegelverlauf \(stationName)",
            summary: summaryParts.joined(separator: ". "),
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        // Bei jedem Refresh wird makeChartDescriptor neu aufgerufen, wenn sich
        // die Identity ändert. Für dynamische Updates hier nichts zu tun.
    }
}
