import CoreSpotlight
import UniformTypeIdentifiers

/// Indexiert die beobachteten Stationen in Spotlight, damit z.B. die Suche
/// nach "Iffezheim" direkt die Detailansicht öffnet
/// (Deep-Link via CSSearchableItemActionType in ContentView).
enum SpotlightIndexer {

    private static let domain = "de.felixschick.pegelwatch.stations"

    static func reindex(_ stations: [WatchedStation]) {
        Task.detached(priority: .utility) {
            let items = stations.map { station in
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
            try? await CSSearchableIndex.default()
                .deleteSearchableItems(withDomainIdentifiers: [domain])
            guard !items.isEmpty else { return }
            try? await CSSearchableIndex.default().indexSearchableItems(items)
        }
    }
}
