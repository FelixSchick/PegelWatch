import SwiftUI
import UserNotifications

struct SettingsView: View {

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showResetConfirm: Bool = false
    @State private var store = StationStore.shared
    @State private var soundSettings = AlarmSoundSettings.shared
    @State private var previewPlayer = SoundPreviewPlayer.shared
    @State private var testNotificationSent = false
    
    @State private var tapCount = 0
    @State private var lastTapTime = Date()
    
    @State private var showDevView = false

    private let refreshIntervalOptions = [5, 10, 15, 30, 60]

    var body: some View {
        NavigationStack {
            Form {
                notificationSection
                alarmSoundSection
                alarmVolumeSection
                aboutSection
                dangerSection
            }
            .navigationTitle("Einstellungen")
            .task {
                await checkNotificationStatus()
            }
            .onDisappear {
                previewPlayer.stop()
            }
            .confirmationDialog(
                "Alle Stationen entfernen?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Alle entfernen", role: .destructive) {
                    store.watchedStations.removeAll()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Diese Aktion kann nicht rückgängig gemacht werden.")
            }
            .sheet(isPresented: $showDevView) {
                DeveloperView()
            }
        }
    }

    // MARK: - Sections

    private var notificationSection: some View {
        Section("Benachrichtigungen") {
            HStack {
                Label("Status", systemImage: notificationIcon)
                Spacer()
                Text(notificationStatusText)
                    .foregroundStyle(notificationStatusColor)
            }

            if notificationStatus == .denied {
                Button("Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else if notificationStatus == .notDetermined {
                Button("Berechtigung erteilen") {
                    Task {
                        await NotificationManager.shared.requestPermission()
                        await checkNotificationStatus()
                    }
                }
            }
        }
    }

    private var alarmSoundSection: some View {
        Section {
            ForEach(AlarmSound.allCases) { sound in
                HStack(spacing: 12) {
                    Button {
                        previewPlayer.toggle(sound, volume: soundSettings.criticalVolume)
                    } label: {
                        Image(systemName: previewPlayer.playingSound == sound
                              ? "stop.circle.fill" : "play.circle")
                            .font(.title3)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)

                    Label(sound.displayName, systemImage: sound.systemImage)

                    Spacer()

                    if soundSettings.alarmSound == sound {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    soundSettings.alarmSound = sound
                }
            }
        } header: {
            Label("Alarmton", systemImage: "speaker.wave.2")
        } footer: {
            Text("Der Ton wird für Pegel-Alarme verwendet. Eigene Alarme können in ihrer Bearbeitung einen abweichenden Ton erhalten.")
        }
    }

    private var alarmVolumeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lautstärke: \(Int(soundSettings.criticalVolume * 100)) %")
                    .font(.subheadline)
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $soundSettings.criticalVolume, in: 0.1...1.0, step: 0.05) { editing in
                        if !editing {
                            previewPlayer.play(soundSettings.alarmSound,
                                               volume: soundSettings.criticalVolume)
                        }
                    }
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $soundSettings.useCriticalAlerts) {
                Label("Kritische Warnung", systemImage: "exclamationmark.triangle")
            }

            Button {
                NotificationManager.shared.sendTestAlarmNotification()
                testNotificationSent = true
                Task {
                    // Solange gesperrt lassen, bis die Testmitteilung (5 s)
                    // zugestellt ist — erneutes Tippen würde sie ersetzen.
                    try? await Task.sleep(for: .seconds(5))
                    testNotificationSent = false
                }
            } label: {
                Label(testNotificationSent ? "Wird in 5 s zugestellt …" : "Testbenachrichtigung senden",
                      systemImage: "bell.and.waves.left.and.right")
            }
            .disabled(testNotificationSent || notificationStatus != .authorized)
        } header: {
            Label("Lautstärke & Dringlichkeit", systemImage: "speaker.wave.3")
        } footer: {
            Text("Kritische Warnungen durchbrechen Stummmodus und Fokus und nutzen die eingestellte Lautstärke. Ohne kritische Warnung folgen Alarme der Systemlautstärke und werden als zeitkritisch zugestellt.")
        }
    }

    private var aboutSection: some View {
        Section("Über PegelWatch") {
            LabeledContent {
                Text(appVersion)
            } label: {
                Label("Version", systemImage: "info.circle")
            }
            .onTapGesture { handleTap() }

            LabeledContent {
                Text("PegelOnline WSV")
            } label: {
                Label("Datenquelle", systemImage: "server.rack")
            }

            Link(destination: URL(string: "https://pegelonline.wsv.de")!) {
                Label("pegelonline.wsv.de", systemImage: "globe")
            }

            LabeledContent {
                Text("\(store.watchedStations.count)")
            } label: {
                Label("Beobachtete Stationen", systemImage: "eye")
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Alle Stationen entfernen", role: .destructive) {
                showResetConfirm = true
            }
            .disabled(store.watchedStations.isEmpty)
        } header: {
            Text("Zurücksetzen")
        }
    }

    // MARK: - Developer

    func handleTap() {
#if DEBUG
            let now = Date()
        
            if now.timeIntervalSince(lastTapTime) > 1.5 {
                tapCount = 0
            }

            tapCount += 1
            lastTapTime = now

            if tapCount >= 5 {
                activateDeveloperMode()
                tapCount = 0
            }
#endif
        }
  
        func activateDeveloperMode() {
            showDevView = true
        }
    
    // MARK: - Helpers

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized:       return "Aktiv"
        case .denied:           return "Gesperrt"
        case .notDetermined:    return "Nicht gesetzt"
        case .provisional:      return "Provisorisch"
        case .ephemeral:        return "Ephemeral"
        @unknown default:       return "Unbekannt"
        }
    }

    private var notificationStatusColor: Color {
        switch notificationStatus {
        case .authorized:   return .green
        case .denied:       return .red
        default:            return .secondary
        }
    }

    private var notificationIcon: String {
        switch notificationStatus {
        case .authorized:   return "bell.fill"
        case .denied:       return "bell.slash.fill"
        default:            return "bell"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
}
