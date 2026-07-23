import CoreSpotlight
import UniformTypeIdentifiers

/// Indexiert die beobachteten Stationen in Spotlight, damit z.B. die Suche
/// nach "Iffezheim" direkt die Detailansicht öffnet
/// (Deep-Link via CSSearchableItemActionType in ContentView).
enum SpotlightIndexer {

    private static let domain = "de.felixschick.pegelwatch.stations"

    /// Kompletter Neuaufbau des Index — nur beim App-Start zur Reconciliation.
    static func reindex(_ stations: [WatchedStation]) {
        Task.detached(priority: .utility) {
            try? await CSSearchableIndex.default()
                .deleteSearchableItems(withDomainIdentifiers: [domain])
            guard !stations.isEmpty else { return }
            try? await CSSearchableIndex.default()
                .indexSearchableItems(stations.map(item(for:)))
        }
    }

    /// Einzelne Station indexieren (beim Hinzufügen).
    static func index(_ station: WatchedStation) {
        Task.detached(priority: .utility) {
            try? await CSSearchableIndex.default()
                .indexSearchableItems([item(for: station)])
        }
    }

    /// Einzelne Station aus dem Index entfernen (beim Löschen).
    static func remove(id: String) {
        Task.detached(priority: .utility) {
            try? await CSSearchableIndex.default()
                .deleteSearchableItems(withIdentifiers: [id])
        }
    }

    private static func item(for station: WatchedStation) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = station.displayName
        attributes.contentDescription =
            "\(station.waterDisplayName) – Pegelstand & Alarme in PegelWatch"
        attributes.keywords = ["Pegel", "Wasserstand", "Hochwasser",
                               station.displayName, station.waterDisplayName]
        return CSSearchableItem(
            uniqueIdentifier: station.id,
            domainIdentifier: domain,
            attributeSet: attributes
        )
    }
}
