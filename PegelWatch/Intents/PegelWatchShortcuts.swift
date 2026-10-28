import AppIntents
import CoreSpotlight
import SwiftUI

// MARK: - Entity

/// Beobachtete Station für Siri/Shortcuts (App-Target-Pendant zur
/// StationAppEntity des Widgets). `IndexedEntity` macht sie zugleich zur
/// Grundlage für den Spotlight-Index (siehe `SpotlightIndexer`).
struct StationEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pegelstation"
    static let defaultQuery = WatchedStationQuery()

    let id: String
    let name: String
    let water: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(water)")
    }

    /// Zusätzliche Spotlight-Metadaten (iOS-18-Basisweg, ohne die iOS-26-Makros
    /// `@ComputedProperty(indexingKey:)`, die hier zu Konformitätsfehlern führten).
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.contentDescription = "\(water) – Pegelstand & Alarme in PegelWatch"
        attributes.keywords = [name, water, "Pegel", "Wasserstand", "Hochwasser"]
        return attributes
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

/// Lässt das System die Spotlight-Entities neu einlesen, wenn eine seiner
/// `CSSearchableIndex`-Instanzen das anfordert (z. B. nach einem Indexfehler).
@available(iOS 27.0, *)
extension WatchedStationQuery: IndexedEntityQuery {
    func reindexEntities(for identifiers: [StationEntity.ID], indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex.default().indexAppEntities(entities(for: identifiers))
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex.default().indexAppEntities(suggestedEntities())
    }
}

// MARK: - Open Intent (Spotlight-Deeplink)

/// Spotlight ruft dieses Intent auf, wenn jemand ein `StationEntity` aus den
/// Suchergebnissen antippt, und öffnet die App direkt in der Detailansicht.
struct OpenStationIntent: OpenIntent {
    static let title: LocalizedStringResource = "Pegelstation öffnen"

    @Parameter(title: "Station")
    var target: StationEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.selectedTab = .watchlist
        AppRouter.shared.pendingStationID = target.id
        return .result()
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

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        guard let watched = StationStore.shared.watchedStations
            .first(where: { $0.id == station.id }) else {
            return .result(
                dialog: IntentDialog(stringLiteral: "\(station.name) ist nicht mehr in deiner Merkliste."),
                snippetIntent: WaterLevelSnippetIntent(station: station)
            )
        }

        // Frischen Wert laden, sonst letzten bekannten verwenden
        let fresh = await LevelDataProvider.currentLevel(for: watched.id)

        guard let value = fresh ?? watched.lastValue else {
            return .result(
                dialog: IntentDialog(stringLiteral: "Für \(watched.displayName) liegen aktuell keine Messdaten vor."),
                snippetIntent: WaterLevelSnippetIntent(station: station)
            )
        }

        // Frischen Wert in den Store schreiben, damit der Snippet-Intent (der nur
        // liest) denselben Stand anzeigt, den der Dialog gerade ansagt.
        if let fresh {
            StationStore.shared.updateLevel(id: watched.id, value: fresh)
        }

        var text = "\(watched.waterDisplayName) bei \(watched.displayName): \(Int(value)) Zentimeter."
        if let threshold = watched.alarmThreshold {
            text += value >= threshold
                ? " Achtung: Die Alarmschwelle von \(Int(threshold)) Zentimetern ist überschritten."
                : " Die Alarmschwelle liegt bei \(Int(threshold)) Zentimetern."
        }

        return .result(
            dialog: IntentDialog(stringLiteral: text),
            snippetIntent: WaterLevelSnippetIntent(station: station)
        )
    }
}

// MARK: - Snippet

/// Rendert die Pegelstand-Karte live aus dem aktuellen Store-Zustand. Liest nur –
/// das System darf `perform()` bei jedem Redraw erneut aufrufen (z. B. nach dem
/// Stumm-Button), daher dürfen hier keine Mutationen oder Netzwerk-Aufrufe stehen.
struct WaterLevelSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Pegelstand-Karte"

    @Parameter var station: StationEntity

    init() {}
    init(station: StationEntity) {
        self.station = station
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        guard let watched = StationStore.shared.watchedStations
            .first(where: { $0.id == station.id }) else {
            return .result(view: WaterLevelSnippetView(
                station: station, value: nil, color: .gray, threshold: nil,
                isMuted: false, hasAlarm: false
            ))
        }
        return .result(view: WaterLevelSnippetView(
            station: station,
            value: watched.lastValue.map(Int.init),
            color: watched.lastValue != nil ? watched.alarmLevel.color : .gray,
            threshold: watched.alarmThreshold,
            isMuted: watched.isAlarmMuted,
            hasAlarm: watched.alarmThreshold != nil
        ))
    }
}

/// Stummschalt-Knopf im interaktiven Snippet. Mutiert den Store und kehrt sofort
/// zurück — das System rendert `WaterLevelSnippetIntent` danach automatisch neu.
struct SetStationMuteIntent: AppIntent {
    static let title: LocalizedStringResource = "Pegel-Alarm stummschalten"
    static let isDiscoverable: Bool = false

    @Parameter var station: StationEntity
    @Parameter var muted: Bool

    init() {}
    init(station: StationEntity, muted: Bool) {
        self.station = station
        self.muted = muted
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if muted {
            StationStore.shared.muteAlarms(for: station.id, duration: AlarmMuteDuration.oneHour.seconds)
        } else {
            StationStore.shared.unmuteAlarms(for: station.id)
        }
        return .result()
    }
}

private struct WaterLevelSnippetView: View {
    let station: StationEntity
    let value: Int?
    let color: Color
    let threshold: Double?
    let isMuted: Bool
    let hasAlarm: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "water.waves")
                    .font(.title2)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name).font(.headline)
                    Text(station.water).font(.caption).foregroundStyle(.secondary)
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
            if hasAlarm {
                Button(intent: SetStationMuteIntent(station: station, muted: !isMuted)) {
                    Label(isMuted ? "Stumm aufheben" : "1 Stunde stumm",
                          systemImage: isMuted ? "bell" : "bell.slash")
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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
