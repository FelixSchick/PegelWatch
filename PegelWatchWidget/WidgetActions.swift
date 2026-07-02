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
