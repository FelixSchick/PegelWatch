import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    // One activity per station (keyed by station UUID)
    private var standardActivities: [String: Activity<PegelWatchActivityAttributes>]  = [:]
    private var criticalActivities: [String: Activity<PegelWatchCriticalActivityAttributes>] = [:]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Public API
    // ─────────────────────────────────────────────────────────────────────────

    /// Call after every level refresh for a station.
    func update(station: WatchedStation) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let level = station.lastValue else { return }

        await endAll()
        
        switch station.alarmLevel {
        case .normal:
            await endStandard(for: station, recovered: false)
            await endCritical(for: station, recovered: false)
        case .warning, .danger:
            await upsertStandard(station: station, level: level)
            await endCritical(for: station, recovered: true)

        case .critical:
            await endStandard(for: station, recovered: false)
            await upsertCritical(station: station, level: level)
        }
    }

    /// End all activities for all stations (e.g. on app quit / watchlist cleared)
    func endAll() async {
        for (id, activity) in standardActivities {
            await activity.end(nil, dismissalPolicy: .immediate)
            standardActivities.removeValue(forKey: id)
        }
        for (id, activity) in criticalActivities {
            await activity.end(nil, dismissalPolicy: .immediate)
            criticalActivities.removeValue(forKey: id)
        }
    }

    func end(for station: WatchedStation) async {
        if let activity = standardActivities[station.id] {
            await activity.end(nil, dismissalPolicy: .immediate)
            standardActivities.removeValue(forKey: station.id)
        }
        if let activity = criticalActivities[station.id] {
            await activity.end(nil, dismissalPolicy: .immediate)
            criticalActivities.removeValue(forKey: station.id)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Standard Activity
    // ─────────────────────────────────────────────────────────────────────────

    private func upsertStandard(station: WatchedStation, level: Double) async {
        let state = PegelWatchActivityAttributes.ContentState(
            currentLevel: level,
            threshold:    station.alarmThreshold,
            alarmLevel:   station.alarmLevel,
            updatedAt:    station.lastUpdated ?? .now,
            trend:        nil
        )
        let content = ActivityContent(
            state:     state,
            staleDate: Date(timeIntervalSinceNow: 30 * 60)
        )

        if let existing = standardActivities[station.id] {
            // Activity already running — just push new state
            await existing.update(content)
            print("already existing live activity")
        } else {
            // Start fresh
            let attrs = PegelWatchActivityAttributes(
                stationName: station.displayName,
                waterName:   station.waterDisplayName,
                stationID:   station.id
            )
            do {
                let activity = try Activity.request(
                    attributes: attrs,
                    content:    content,
                    pushType:   nil
                )
                standardActivities[station.id] = activity
                print("[PegelWatch] 🟢 Standard Live Activity started for \(station.displayName)")
            } catch {
                print("[PegelWatch] ⚠️ Could not start standard Live Activity: \(error.localizedDescription)")
            }
        }
    }

    private func endStandard(for station: WatchedStation, recovered: Bool) async {
        guard let activity = standardActivities[station.id] else { return }
        let policy: ActivityUIDismissalPolicy = recovered ? .after(.now + 4) : .immediate
        await activity.end(nil, dismissalPolicy: policy)
        standardActivities.removeValue(forKey: station.id)
        print("[PegelWatch] ⛔ Standard Live Activity ended for \(station.displayName)")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Critical Activity
    // ─────────────────────────────────────────────────────────────────────────

    private func upsertCritical(station: WatchedStation, level: Double) async {
        guard let threshold = station.alarmThreshold else { return }

        let state = PegelWatchCriticalActivityAttributes.ContentState(
            currentLevel: level,
            threshold:    threshold,
            trend:        nil,
            updatedAt:    station.lastUpdated ?? .now,
            hasRecovered: false
        )
        let content = ActivityContent(
            state:     state,
            staleDate: Date(timeIntervalSinceNow: 30 * 60)
        )

        if let existing = criticalActivities[station.id] {
            // Already running — update level without re-alerting
            await existing.update(content)
        } else {
            let attrs = PegelWatchCriticalActivityAttributes(
                stationName: station.displayName,
                waterName:   station.waterDisplayName,
                stationID:   station.id,
                km:          station.km
            )
            do {
                let activity = try Activity.request(
                    attributes: attrs,
                    content:    content,
                    pushType:   nil
                )
                criticalActivities[station.id] = activity
                print("[PegelWatch] 🔴 Critical Live Activity started for \(station.displayName)")
            } catch {
                print("[PegelWatch] ⚠️ Could not start critical Live Activity: \(error.localizedDescription)")
            }
        }
    }

    private func endCritical(for station: WatchedStation, recovered: Bool) async {
        guard let activity = criticalActivities[station.id] else { return }

        if recovered, let level = station.lastValue, let threshold = station.alarmThreshold {
            let recoveredState = PegelWatchCriticalActivityAttributes.ContentState(
                currentLevel: level,
                threshold:    threshold,
                trend:        nil,
                updatedAt:    .now,
                hasRecovered: true
            )
            let content = ActivityContent(state: recoveredState, staleDate: .now + 4)
            await activity.end(content, dismissalPolicy: .after(.now + 4))
        } else {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        criticalActivities.removeValue(forKey: station.id)
        print("[PegelWatch] ✅ Critical Live Activity ended for \(station.displayName)")
    }
}
