//
//  PegelWatchCriticalActivityAttributes.swift
//  PegelWatch
//
//  Created by Felix Schick on 30.03.26.
//


import ActivityKit
import SwiftUI
import WidgetKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Attributes
// ─────────────────────────────────────────────────────────────────────────────

public struct PegelWatchCriticalActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        /// Current water level in cm
        public var currentLevel: Double
        /// The configured alarm threshold in cm
        public var threshold: Double
        /// How far above the threshold in cm  (currentLevel – threshold)
        public var exceedanceAmount: Double { max(currentLevel - threshold, 0) }
        /// Exceedance as a percentage of the threshold (e.g. 120% → 20%)
        public var exceedancePercent: Double { currentLevel / threshold * 100 }
        /// Trend in cm/h
        public var trend: Double?
        /// Time of this reading
        public var updatedAt: Date

        /// True when the station has recovered (used for dismissal banner)
        public var hasRecovered: Bool = false
    }

    /// Station display name
    public var stationName: String
    /// Water body name
    public var waterName: String
    /// UUID for deep-linking
    public var stationID: String
    /// River kilometer (optional cosmetic)
    public var km: Double?
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Widget declaration
// ─────────────────────────────────────────────────────────────────────────────

struct PegelWatchCriticalLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PegelWatchCriticalActivityAttributes.self) { context in

            // ── Lock Screen / Notification Banner ─────────────────────────
            CriticalLockScreenView(
                attributes: context.attributes,
                state:      context.state
            )
            // Bright red tint so iOS automatically uses it as a banner accent
            .activityBackgroundTint(Color.red.opacity(0.08))

        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded ──────────────────────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    criticalExpandedLeading(attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    criticalExpandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    criticalExpandedCenter(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    criticalExpandedBottom(state: context.state)
                }
            } compactLeading: {
                // Pulsing exclamation for immediate visual urgency
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse.byLayer)

            } compactTrailing: {
                Text("\(Int(context.state.currentLevel))cm")
                    .font(.caption2.weight(.black).monospacedDigit())
                    .foregroundStyle(.red)

            } minimal: {
                Image(systemName: "exclamationmark.3")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            }
            .keylineTint(.red)  // red ring around the Dynamic Island pill
            .widgetURL(URL(string: "pegelwatch://station/\(context.attributes.stationID)"))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Lock Screen View
// ─────────────────────────────────────────────────────────────────────────────

struct CriticalLockScreenView: View {
    let attributes: PegelWatchCriticalActivityAttributes
    let state:      PegelWatchCriticalActivityAttributes.ContentState

    var body: some View {
        if state.hasRecovered {
            recoveredBanner
        } else {
            activeCriticalBanner
        }
    }

    // ── Active critical ────────────────────────────────────────────────────

    private var activeCriticalBanner: some View {
        VStack(spacing: 10) {

            // ── Top row: icon + title + level ────────────────────────────
            HStack(spacing: 12) {

                // Pulsing warning ring
                ZStack {
                    Circle()
                        .strokeBorder(.red.opacity(0.25), lineWidth: 6)
                        .frame(width: 52, height: 52)
                        .symbolEffect(.pulse)
                    Circle()
                        .fill(.red.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "exclamationmark.3")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse.byLayer)
                }

                VStack(alignment: .leading, spacing: 3) {
                    // "KRITISCH" badge
                    Text("KRITISCH")
                        .font(.caption.weight(.black))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.red, in: Capsule())

                    HStack(spacing: 4) {
                        Text(attributes.stationName)
                            .font(.subheadline.weight(.semibold))
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(attributes.waterName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)

                    if let km = attributes.km {
                        Text("Flusskilometer \(String(format: "%.1f", km))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Big level reading
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(state.currentLevel))")
                            .font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.red)
                            .contentTransition(.numericText())
                        Text("cm")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    }
                    Text("+ \(String(format: "%.0f", state.exceedanceAmount)) cm")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.red.opacity(0.8))
                }
            }

            // ── Bottom row: threshold bar + trend ────────────────────────
            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(Color(.systemFill))
                            .frame(height: 7)
                        // Fill up to 1× threshold (= 100%)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .leading,
                                endPoint:   .trailing
                            ))
                            .frame(
                                width: min(geo.size.width, geo.size.width * (state.currentLevel / (state.threshold * 1.5))),
                                height: 7
                            )
                        // Threshold marker
                        let markerX = geo.size.width * (state.threshold / (state.threshold * 1.5))
                        Rectangle()
                            .fill(.red)
                            .frame(width: 2, height: 11)
                            .offset(x: markerX - 1, y: -2)
                    }
                }
                .frame(height: 7)

                HStack {
                    Text("0 cm")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Text("Schwelle: \(Int(state.threshold)) cm")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                    Spacer()
                    if let trend = state.trend {
                        let arrow = trend > 0 ? "↑" : (trend < 0 ? "↓" : "→")
                        Text("\(arrow) \(String(format: "%.1f", abs(trend))) cm/h")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(trend > 0 ? .red : .teal)
                    } else {
                        Text("\(Int(state.threshold * 1.5)) cm")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            // ── Timestamp ────────────────────────────────────────────────
            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                Text("Aktualisiert \(state.updatedAt, style: .relative)")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // ── Recovery banner (shown for a few seconds after ending) ─────────────

    private var recoveredBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Entwarnung")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.teal)
                Text("\(attributes.stationName) · \(Int(state.currentLevel)) cm — Pegel ist gesunken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Dynamic Island Expanded Regions
// ─────────────────────────────────────────────────────────────────────────────

private func criticalExpandedLeading(
    attributes: PegelWatchCriticalActivityAttributes
) -> some View {
    HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.black))
            .foregroundStyle(.red)
            .symbolEffect(.pulse.byLayer)
        VStack(alignment: .leading, spacing: 1) {
            Text(attributes.stationName)
                .font(.caption.weight(.bold))
                .foregroundStyle(.red)
                .lineLimit(1)
            Text(attributes.waterName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
    .padding(.leading, 4)
}

private func criticalExpandedTrailing(
    state: PegelWatchCriticalActivityAttributes.ContentState
) -> some View {
    VStack(alignment: .trailing, spacing: 1) {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(Int(state.currentLevel))")
                .font(.system(.title2, design: .rounded).weight(.black).monospacedDigit())
                .foregroundStyle(.red)
                .contentTransition(.numericText())
            Text("cm")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Text("+ \(String(format: "%.0f", state.exceedanceAmount)) cm")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.red.opacity(0.7))
    }
    .padding(.trailing, 4)
}

private func criticalExpandedCenter(
    state: PegelWatchCriticalActivityAttributes.ContentState
) -> some View {
    Text("KRITISCH")
        .font(.caption2.weight(.black))
        .tracking(1.5)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.red, in: Capsule())
}

private func criticalExpandedBottom(
    state: PegelWatchCriticalActivityAttributes.ContentState
) -> some View {
    VStack(spacing: 6) {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemFill))
                    .frame(height: 6)
                Capsule()
                    .fill(LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(
                        width: min(geo.size.width, geo.size.width * (state.currentLevel / (state.threshold * 1.5))),
                        height: 6
                    )
                let markerX = geo.size.width * (state.threshold / (state.threshold * 1.5))
                Rectangle()
                    .fill(.red)
                    .frame(width: 2, height: 10)
                    .offset(x: markerX - 1, y: -2)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 16)

        HStack {
            Text("0 cm")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Text("Schwelle: \(Int(state.threshold)) cm")
                .font(.caption2.weight(.semibold)).foregroundStyle(.red)
            Spacer()
            if let trend = state.trend {
                let arrow = trend > 0 ? "↑" : "↓"
                Text("\(arrow) \(String(format: "%.1f", abs(trend))) cm/h")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(trend > 0 ? .red : .teal)
            } else {
                Text("\(Int(state.threshold * 1.5)) cm")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
    }
    .padding(.bottom, 8)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview helpers
// ─────────────────────────────────────────────────────────────────────────────

extension PegelWatchCriticalActivityAttributes {
    static let preview = PegelWatchCriticalActivityAttributes(
        stationName: "Koblenz",
        waterName:   "Rhein",
        stationID:   "3da9ddb7-a8dc-400e-8fe5-db2e9a347d90",
        km:          590.3
    )
    static func previewState(
        level: Double = 305,
        threshold: Double = 250,
        trend: Double? = 2.8,
        recovered: Bool = false
    ) -> ContentState {
        ContentState(
            currentLevel: level,
            threshold:    threshold,
            trend:        trend,
            updatedAt:    .now,
            hasRecovered: recovered
        )
    }
}

#Preview("Lock Screen – Critical", as: .content,
         using: PegelWatchCriticalActivityAttributes.preview) {
    PegelWatchCriticalLiveActivityWidget()
} contentStates: {
    PegelWatchCriticalActivityAttributes.previewState()
}

#Preview("Lock Screen – Recovered", as: .content,
         using: PegelWatchCriticalActivityAttributes.preview) {
    PegelWatchCriticalLiveActivityWidget()
} contentStates: {
    PegelWatchCriticalActivityAttributes.previewState(level: 230, trend: -1.2, recovered: true)
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded),
         using: PegelWatchCriticalActivityAttributes.preview) {
    PegelWatchCriticalLiveActivityWidget()
} contentStates: {
    PegelWatchCriticalActivityAttributes.previewState()
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact),
         using: PegelWatchCriticalActivityAttributes.preview) {
    PegelWatchCriticalLiveActivityWidget()
} contentStates: {
    PegelWatchCriticalActivityAttributes.previewState()
}
