import AppIntents
import SwiftUI
import WidgetKit

/// Interaktiver Widget-Button: löst nach Abschluss automatisch ein
/// Timeline-Reload aus, wodurch der Provider frische Pegel lädt.
struct RefreshWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Pegel aktualisieren"
    static let description = IntentDescription("Lädt die aktuellen Wasserstände neu.")

    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Öffnet die App aus dem Kontrollzentrum.
struct OpenPegelWatchIntent: AppIntent {
    static let title: LocalizedStringResource = "PegelWatch öffnen"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Schaltet alle Alarme für eine feste Dauer stumm. Läuft in-process im
/// Widget-Extension und schreibt via App-Group UserDefaults zurück – die
/// Hauptapp und alle Widgets sehen die Änderung sofort.
struct MuteAllAlarmsWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Alle Alarme stumm"
    static let description = IntentDescription("Schaltet alle Alarme für 1 Stunde stumm.")

    func perform() async throws -> some IntentResult {
        let suite = UserDefaults(suiteName: "group.de.felixschick.pegelwatch") ?? .standard
        let key = "de.felixschick.pegelwatch.watched_stations"

        guard
            let data = suite.data(forKey: key),
            var stations = try? JSONDecoder().decode([WatchedStation].self, from: data)
        else {
            return .result()
        }

        let mutedUntil = Date().addingTimeInterval(60 * 60)
        for i in stations.indices {
            stations[i].alarmMutedUntil = mutedUntil
        }

        if let encoded = try? JSONEncoder().encode(stations) {
            suite.set(encoded, forKey: key)
        }

        // Alle Widgets neu laden — die "stumm"-Info erscheint dadurch überall.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Control-Center-Baustein: schneller Absprung in die Pegel-Übersicht.
struct PegelWatchOpenControl: ControlWidget {
    static let kind = "de.felixschick.pegelwatch.open"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenPegelWatchIntent()) {
                Label("PegelWatch", systemImage: "water.waves")
            }
        }
        .displayName("PegelWatch")
        .description("Öffnet die Pegel-Übersicht.")
    }
}

/// Zweites Control-Center-Widget: alle Alarme mit einem Tap für 1 h stumm.
struct PegelWatchMuteControl: ControlWidget {
    static let kind = "de.felixschick.pegelwatch.mute"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: MuteAllAlarmsWidgetIntent()) {
                Label("Alarme stumm", systemImage: "bell.slash")
            }
        }
        .displayName("Alarme stumm (1 h)")
        .description("Schaltet alle Pegel-Alarme für eine Stunde stumm.")
    }
}
