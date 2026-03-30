//
//  PegelWatchActivityAttributes.swift
//  PegelWatch
//
//  Created by Felix Schick on 30.03.26.
//


import ActivityKit
import SwiftUI
import WidgetKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Attributes (static data that never changes for this activity)
// ─────────────────────────────────────────────────────────────────────────────

public struct PegelWatchActivityAttributes: ActivityAttributes {

    /// The mutable part — pushed with every API refresh
    public struct ContentState: Codable, Hashable {
        /// Water level in cm
        public var currentLevel: Double
        /// Alarm threshold in cm (nil = none set)
        public var threshold: Double?
        /// Current alarm level derived from level vs threshold
        public var alarmLevel: AlarmLevel
        /// Last time the live data was fetched
        public var updatedAt: Date
        /// Trend in cm/hour (positive = rising, negative = falling)
        public var trend: Double?

        /// Fill fraction 0–1 toward threshold (capped at 1.5× threshold)
        public var fillFraction: Double {
            guard let level = threshold, level > 0 else { return 0 }
            return min(currentLevel / (level * 1.5), 1.0)
        }

        /// Formatted trend arrow + value
        public var trendText: String? {
            guard let t = trend else { return nil }
            let arrow = t > 0 ? "↑" : (t < 0 ? "↓" : "→")
            return "\(arrow) \(String(format: "%.1f", abs(t))) cm/h"
        }
    }

    /// Station display name, e.g. "Koblenz"
    public var stationName: String
    /// Water body, e.g. "Rhein"
    public var waterName: String
    /// UUID — used as deep-link target
    public var stationID: String
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Widget declaration (registers the Live Activity in the bundle)
// ─────────────────────────────────────────────────────────────────────────────

struct PegelWatchLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PegelWatchActivityAttributes.self) { context in
            // ── Lock Screen / Notification Banner ─────────────────────────────
            PegelWatchLockScreenView(
                attributes: context.attributes,
                state:      context.state
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color(.systemBackground))

        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded ────────────────────────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    expandedCenter(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                // ── Compact Leading ──────────────────────────────────────────
                Image(systemName: "water.waves")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(context.state.alarmLevel.color)

            } compactTrailing: {
                // ── Compact Trailing ─────────────────────────────────────────
                Text("\(Int(context.state.currentLevel))cm")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(context.state.alarmLevel.color)

            } minimal: {
                // ── Minimal (when two activities compete) ────────────────────
                Image(systemName: context.state.alarmLevel.systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(context.state.alarmLevel.color)
            }
            .widgetURL(URL(string: "pegelwatch://station/\(context.attributes.stationID)"))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Lock Screen View
// ─────────────────────────────────────────────────────────────────────────────

struct PegelWatchLockScreenView: View {
    let attributes: PegelWatchActivityAttributes
    let state: PegelWatchActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {

            // ── Left: alarm indicator ────────────────────────────────────────
            ZStack {
                Circle()
                    .fill(state.alarmLevel.color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: state.alarmLevel.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(state.alarmLevel.color)
                    .symbolEffect(.pulse, isActive: state.alarmLevel.isAlarming)
            }

            // ── Middle: station info ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(attributes.stationName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(attributes.waterName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Fill bar
                if state.threshold != nil {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemFill))
                                .frame(height: 5)
                            Capsule()
                                .fill(state.alarmLevel.color)
                                .frame(width: geo.size.width * state.fillFraction, height: 5)
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        Text("Schwelle \(state.threshold.map { "\(Int($0)) cm" } ?? "–")")
                        Spacer()
                        if let trend = state.trendText {
                            Text(trend)
                                .foregroundStyle(state.trend ?? 0 > 0 ? .orange : .teal)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Text("Zuletzt: \(state.updatedAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // ── Right: big level number ──────────────────────────────────────
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(state.currentLevel))")
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(state.alarmLevel.color)
                    .contentTransition(.numericText())
                Text("cm")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(state.alarmLevel.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state.alarmLevel.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(state.alarmLevel.color.opacity(0.12), in: Capsule())
                    .padding(.top, 2)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Dynamic Island Expanded Regions
// ─────────────────────────────────────────────────────────────────────────────

private func expandedLeading(
    attributes: PegelWatchActivityAttributes,
    state: PegelWatchActivityAttributes.ContentState
) -> some View {
    HStack(spacing: 6) {
        Image(systemName: "water.waves")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.blue)
        VStack(alignment: .leading, spacing: 1) {
            Text(attributes.stationName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(attributes.waterName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
    .padding(.leading, 4)
}

private func expandedTrailing(
    state: PegelWatchActivityAttributes.ContentState
) -> some View {
    VStack(alignment: .trailing, spacing: 1) {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(Int(state.currentLevel))")
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(state.alarmLevel.color)
                .contentTransition(.numericText())
            Text("cm")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let trend = state.trendText {
            Text(trend)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(state.trend ?? 0 > 0 ? .orange : .teal)
        }
    }
    .padding(.trailing, 4)
}

private func expandedCenter(
    attributes: PegelWatchActivityAttributes,
    state: PegelWatchActivityAttributes.ContentState
) -> some View {
    Label(state.alarmLevel.label, systemImage: state.alarmLevel.systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(state.alarmLevel.color)
        .symbolEffect(.pulse, isActive: state.alarmLevel.isAlarming)
}

private func expandedBottom(
    state: PegelWatchActivityAttributes.ContentState
) -> some View {
    VStack(spacing: 6) {
        if let threshold = state.threshold {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemFill))
                        .frame(height: 6)
                    Capsule()
                        .fill(state.alarmLevel.color)
                        .frame(width: geo.size.width * state.fillFraction, height: 6)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 16)

            HStack {
                Text("0 cm")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("Schwelle: \(Int(threshold)) cm")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(state.alarmLevel.color)
                Spacer()
                Text("\(Int(threshold * 1.5)) cm")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
        }
    }
    .padding(.bottom, 8)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────────────────────────────────────

extension PegelWatchActivityAttributes {
    static let preview = PegelWatchActivityAttributes(
        stationName: "Koblenz",
        waterName:   "Rhein",
        stationID:   "3da9ddb7-a8dc-400e-8fe5-db2e9a347d90"
    )
    static func previewState(level: Double, alarm: AlarmLevel) -> ContentState {
        ContentState(
            currentLevel: level,
            threshold:    250,
            alarmLevel:   alarm,
            updatedAt:    .now,
            trend:        1.4
        )
    }
}

#Preview("Lock Screen – Normal", as: .content,
         using: PegelWatchActivityAttributes.preview) {
    PegelWatchLiveActivityWidget()
} contentStates: {
    PegelWatchActivityAttributes.previewState(level: 182, alarm: .normal)
}

#Preview("Lock Screen – Warning", as: .content,
         using: PegelWatchActivityAttributes.preview) {
    PegelWatchLiveActivityWidget()
} contentStates: {
    PegelWatchActivityAttributes.previewState(level: 210, alarm: .warning)
}

#Preview("Lock Screen – Danger", as: .content,
         using: PegelWatchActivityAttributes.preview) {
    PegelWatchLiveActivityWidget()
} contentStates: {
    PegelWatchActivityAttributes.previewState(level: 245, alarm: .danger)
}

#Preview("Dynamic Island Expanded – Warning", as: .dynamicIsland(.expanded),
         using: PegelWatchActivityAttributes.preview) {
    PegelWatchLiveActivityWidget()
} contentStates: {
    PegelWatchActivityAttributes.previewState(level: 210, alarm: .warning)
}
