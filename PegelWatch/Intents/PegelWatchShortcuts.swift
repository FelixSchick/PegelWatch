import AppIntents
import SwiftUI

// MARK: - Entity

/// Beobachtete Station für Siri/Shortcuts (App-Target-Pendant zur
/// StationAppEntity des Widgets).
struct StationEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pegelstation"
    static let defaultQuery = WatchedStationQuery()

    let id: String
    let name: String
    let water: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(water)")
    }

    init(from station: WatchedStation) {
        id    = station.id
        name  = station.displayName
        water = station.waterDisplayName
    }
}

struct WatchedStationQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        StationStore.shared.watchedStations
            .filter { identifiers.contains($0.id) }
            .map(StationEntity.init(from:))
    }

    func suggestedEntities() async throws -> [StationEntity] {
        StationStore.shared.watchedStations.map(StationEntity.init(from:))
    }

    func entities(matching string: String) async throws -> [StationEntity] {
        StationStore.shared.watchedStations
            .filter {
                $0.displayName.localizedCaseInsensitiveContains(string) ||
                $0.waterDisplayName.localizedCaseInsensitiveContains(string)
            }
            .map(StationEntity.init(from:))
    }
}

// MARK: - Intent

/// "Wie hoch ist der Pegel in …?" – fragt live den aktuellen Wasserstand ab.
struct GetWaterLevelIntent: AppIntent {
    static let title: LocalizedStringResource = "Pegelstand abfragen"
    static let description = IntentDescription(
        "Fragt den aktuellen Wasserstand einer beobachteten Station ab."
    )

    @Parameter(title: "Station")
    var station: StationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Pegelstand von \(\.$station)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let watched = StationStore.shared.watchedStations
            .first(where: { $0.id == station.id }) else {
            return .result(
                dialog: IntentDialog(stringLiteral: "\(station.name) ist nicht mehr in deiner Watchlist."),
                view: WaterLevelSnippetView(name: station.name, water: station.water,
                                            value: nil, color: .gray, threshold: nil)
            )
        }

        // Frischen Wert laden, sonst letzten bekannten verwenden
        let fresh = await LevelDataProvider.currentLevel(for: watched.id)

        guard let value = fresh ?? watched.lastValue else {
            return .result(
                dialog: IntentDialog(stringLiteral: "Für \(watched.displayName) liegen aktuell keine Messdaten vor."),
                view: WaterLevelSnippetView(name: watched.displayName, water: watched.waterDisplayName,
                                            value: nil, color: .gray, threshold: watched.alarmThreshold)
            )
        }

        var snapshot = watched
        snapshot.lastValue = value

        var text = "\(watched.waterDisplayName) bei \(watched.displayName): \(Int(value)) Zentimeter."
        if let threshold = watched.alarmThreshold {
            text += value >= threshold
                ? " Achtung: Die Alarmschwelle von \(Int(threshold)) Zentimetern ist überschritten."
                : " Die Alarmschwelle liegt bei \(Int(threshold)) Zentimetern."
        }

        return .result(
            dialog: IntentDialog(stringLiteral: text),
            view: WaterLevelSnippetView(name: watched.displayName, water: watched.waterDisplayName,
                                        value: Int(value), color: snapshot.alarmLevel.color,
                                        threshold: watched.alarmThreshold)
        )
    }
}

// MARK: - Snippet

private struct WaterLevelSnippetView: View {
    let name: String
    let water: String
    let value: Int?
    let color: Color
    let threshold: Double?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "water.waves")
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(water).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value.map { "\($0) cm" } ?? "–")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(color)
                if let threshold {
                    Text("Schwelle \(Int(threshold)) cm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: - Refresh All Intent

/// Aktualisiert alle beobachteten Stationen — nützlich als Siri-Shortcut
/// oder als Automatisierungs-Trigger (z. B. bei Ankunft zu Hause).
struct RefreshAllStationsIntent: AppIntent {
    static let title: LocalizedStringResource = "Alle Pegel aktualisieren"
    static let description = IntentDescription(
        "Lädt für alle beobachteten Stationen die aktuellen Wasserstände neu."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = StationStore.shared
        await store.refreshAll()

        let count = store.watchedStations.count
        let alarming = store.watchedStations.filter { $0.alarmLevel.isAlarming }.count

        let dialog: String
        if count == 0 {
            dialog = "Du beobachtest aktuell keine Stationen."
        } else if alarming == 0 {
            dialog = "\(count) Station\(count == 1 ? "" : "en") aktualisiert. Alle Werte sind im Normbereich."
        } else {
            dialog = "\(count) Station\(count == 1 ? "" : "en") aktualisiert. \(alarming) Station\(alarming == 1 ? "" : "en") überschreitet den Alarmwert."
        }

        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - Mute All Intent

struct MuteAllAlarmsIntent: AppIntent {
    static let title: LocalizedStringResource = "Alle Alarme stumm schalten"
    static let description = IntentDescription(
        "Schaltet die Alarme aller beobachteten Stationen vorübergehend stumm."
    )

    @Parameter(title: "Dauer", default: .oneHour)
    var duration: MuteDurationAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Alle Alarme für \(\.$duration) stumm")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = StationStore.shared
        let seconds = duration.underlying.seconds
        for station in store.watchedStations {
            store.muteAlarms(for: station.id, duration: seconds)
        }
        let count = store.watchedStations.count
        return .result(
            dialog: IntentDialog(stringLiteral: "\(count) Station\(count == 1 ? "" : "en") für \(duration.underlying.label) stumm geschaltet.")
        )
    }
}

enum MuteDurationAppEnum: String, AppEnum {
    case oneHour
    case sixHours
    case oneDay

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stumm-Dauer"
    static let caseDisplayRepresentations: [MuteDurationAppEnum: DisplayRepresentation] = [
        .oneHour:  "1 Stunde",
        .sixHours: "6 Stunden",
        .oneDay:   "24 Stunden"
    ]

    var underlying: AlarmMuteDuration {
        switch self {
        case .oneHour:  return .oneHour
        case .sixHours: return .sixHours
        case .oneDay:   return .oneDay
        }
    }
}

// MARK: - App Shortcuts

struct PegelWatchAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetWaterLevelIntent(),
            phrases: [
                "Wie hoch ist der Pegel in \(.applicationName)",
                "Zeige den Pegelstand in \(.applicationName)",
                "Pegelstand von \(\.$station) in \(.applicationName)"
            ],
            shortTitle: "Pegelstand",
            systemImageName: "water.waves"
        )
        AppShortcut(
            intent: RefreshAllStationsIntent(),
            phrases: [
                "Alle Pegel in \(.applicationName) aktualisieren",
                "Aktualisiere \(.applicationName)"
            ],
            shortTitle: "Alle aktualisieren",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: MuteAllAlarmsIntent(),
            phrases: [
                "Alle Alarme in \(.applicationName) stumm schalten",
                "\(.applicationName) stumm"
            ],
            shortTitle: "Alle stumm",
            systemImageName: "bell.slash"
        )
    }
}
