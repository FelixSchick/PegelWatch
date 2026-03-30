//
//  LiveActivityManager.swift
//  PegelWatch
//
//  Created by Felix Schick on 30.03.26.
//



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
            // End both activities when the station is completely fine
            await endStandard(for: station, recovered: false)
            await endCritical(for: station, recovered: false)

        case .warning, .danger:
            // Ensure standard activity is running; end critical if it was
            await upsertStandard(station: station, level: level)
            await endCritical(for: station, recovered: true)

        case .critical:
            // Ensure critical activity is running; end standard
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
        for (id, activity) in standardActivities {
            if id != station.id { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
            standardActivities.removeValue(forKey: id)
        }
        for (id, activity) in criticalActivities {
            if id != station.id { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
            criticalActivities.removeValue(forKey: id)
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
            trend:        nil   // wire up trend calculation here if available
        )

        if let existing = standardActivities[station.id] {
            // Update existing
            await existing.update(
                ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 30 * 60))
            )
        } else {
            // Start new
            let attrs = PegelWatchActivityAttributes(
                stationName: station.displayName,
                waterName:   station.waterDisplayName,
                stationID:   station.id
            )
            let content = ActivityContent(
                state:     state,
                staleDate: Date(timeIntervalSinceNow: 30 * 60)
            )
            do {
                let activity = try Activity.request(
                    attributes: attrs,
                    content:    content,
                    pushType:   nil   // set to .token if you add push updates later
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

        if let existing = criticalActivities[station.id] {
            await existing.update(
                ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 30 * 60)),
                alertConfiguration: AlertConfiguration(
                    title: "⚠️ \(station.displayName) – Kritisch",
                    body: "Pegel: \(Int(level)) cm / Schwelle: \(Int(threshold)) cm",
                    sound: .default
                )
            )
        } else {
            let attrs = PegelWatchCriticalActivityAttributes(
                stationName: station.displayName,
                waterName:   station.waterDisplayName,
                stationID:   station.id,
                km:          station.km
            )
            let content = ActivityContent(
                state:     state,
                staleDate: Date(timeIntervalSinceNow: 30 * 60)
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
        guard let activity = criticalActivities[station.id],
              let level = station.lastValue,
              let threshold = station.alarmThreshold
        else { return }

        if recovered {
            // Push a "recovered" state before dismissing so the banner shows "Entwarnung"
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
