import Observation

/// Einfaches App-Routing für Deep-Links (Spotlight, Mitteilungen):
/// setzt Tab und die zu öffnende Station; die Views reagieren darauf.
@Observable
final class AppRouter {

    static let shared = AppRouter()

    var selectedTab: Int = 0

    /// Stations-ID, deren Detailansicht geöffnet werden soll.
    var pendingStationID: String?
}
