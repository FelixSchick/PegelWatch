import CoreSpotlight

/// Indexiert die beobachteten Stationen als App-Intents-Entities (`StationEntity`)
/// in Spotlight, damit z. B. die Suche nach "Iffezheim" das Entity liefert und
/// `OpenStationIntent` beim Antippen direkt die Detailansicht öffnet.
enum SpotlightIndexer {

    /// Domain der alten, Item-basierten Indexierung (vor der Umstellung auf
    /// `IndexedEntity`) — wird einmalig geräumt, damit keine Dubletten entstehen.
    private static let legacyDomain = "de.felixschick.pegelwatch.stations"

    /// Kompletter Neuaufbau des Index — nur beim App-Start zur Reconciliation.
    static func reindex(_ stations: [WatchedStation]) {
        Task.detached(priority: .utility) {
            try? await CSSearchableIndex.default()
                .deleteSearchableItems(withDomainIdentifiers: [legacyDomain])
            try? await CSSearchableIndex.default()
                .deleteAppEntities(ofType: StationEntity.self)
            guard !stations.isEmpty else { return }
            try? await CSSearchableIndex.default()
                .indexAppEntities(stations.map(StationEntity.init(from:)))
        }
    }

    /// Einzelne Station indexieren (beim Hinzufügen).
    static func index(_ station: WatchedStation) {
        Task.detached(priority: .utility) {
            try? await CSSearchableIndex.default()
                .indexAppEntities([StationEntity(from: station)])
        }
    }

    /// Einzelne Station aus dem Index entfernen (beim Löschen).
    static func remove(id: String) {
        Task.detached(priority: .utility) {
            try? await CSSearchableIndex.default()
                .deleteAppEntities(identifiedBy: [id], ofType: StationEntity.self)
        }
    }
}
