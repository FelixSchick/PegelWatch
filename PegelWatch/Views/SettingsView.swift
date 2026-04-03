import SwiftUI
import UserNotifications

struct SettingsView: View {

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showResetConfirm: Bool = false
    @State private var store = StationStore.shared
    
    @State private var tapCount = 0
    @State private var lastTapTime = Date()
    
    @State private var showDevView = false

    private let refreshIntervalOptions = [5, 10, 15, 30, 60]

    var body: some View {
        NavigationStack {
            Form {
                notificationSection
                aboutSection
                dangerSection
            }
            .navigationTitle("Einstellungen")
            .task {
                await checkNotificationStatus()
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

    private var aboutSection: some View {
        Section("Über PegelWatch") {
            LabeledContent("Version", value: appVersion).onTapGesture {
                handleTap()
            }
            LabeledContent("Datenquelle", value: "PegelOnline WSV")
            Link(
                "pegelonline.wsv.de",
                destination: URL(string: "https://pegelonline.wsv.de")!
            )
            LabeledContent("Beobachtete Stationen", value: "\(store.watchedStations.count)")
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
