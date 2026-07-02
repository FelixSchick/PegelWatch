import Observation

/// Die Tabs der App — benannt statt magischer Integer-Tags,
/// damit Deep-Links Umsortierungen überleben.
enum AppTab: Hashable {
    case watchlist, map, search, settings
}

/// Einfaches App-Routing für Deep-Links (Spotlight, Mitteilungen):
/// setzt Tab und die zu öffnende Station; die Views reagieren darauf.
@Observable
final class AppRouter {

    static let shared = AppRouter()

    var selectedTab: AppTab = .watchlist

    /// Stations-ID, deren Detailansicht geöffnet werden soll.
    var pendingStationID: String?
}
