//
//  PegelWatchWidgetEntry.swift
//  PegelWatch
//
//  Created by Felix Schick on 30.03.26.
//

import SwiftUI
import WidgetKit

struct PegelWatchWidgetEntry: TimelineEntry {
    let date: Date
    let stations: [WatchedStation]   // [pinned] for small/medium, all for large
    let allStations: [WatchedStation] // always full list (used by large widget)

    var primary: WatchedStation? { stations.first }

    static let placeholder = PegelWatchWidgetEntry(
        date: .now,
        stations: [.preview],
        allStations: [.preview, .previewAlarming]
    )
}

// MARK: - Shared helpers

private func loadAllStationsFromDefaults() -> [WatchedStation] {
    let defaults = UserDefaults(suiteName: "group.de.felixschick.pegelwatch") ?? .standard
    guard
        let data    = defaults.data(forKey: "de.felixschick.pegelwatch.watched_stations"),
        let decoded = try? JSONDecoder().decode([WatchedStation].self, from: data)
    else { return [] }
    return decoded
}

private func fetchAndUpdate(_ stations: [WatchedStation]) async -> [WatchedStation] {
    let ids = stations.map { $0.id }
    guard !ids.isEmpty else { return stations }

    let pegelIDs = ids.filter { !HeichwaasserAPI.isLuxembourgStation($0) }
    let luxIDs = ids.filter { HeichwaasserAPI.isLuxembourgStation($0) }

    async let pegelResult = PegelOnlineAPI.shared.fetchLevels(for: pegelIDs)
    async let luxResult = HeichwaasserAPI.shared.fetchLevels(for: luxIDs)

    let (pegelData, luxData) = await (pegelResult, luxResult)

    var levels = pegelData.levels
    for (id, value) in luxData.levels { levels[id] = value }

    var updated = stations
    for i in updated.indices {
        if let v = levels[updated[i].id] {
            updated[i].previousValue = updated[i].lastValue
            updated[i].lastValue   = v
            updated[i].lastUpdated = Date()
        }
    }
    return updated
}

// MARK: - Small/Medium Provider (configurable — user picks a station)

struct PegelWatchWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = SelectStationIntent

    func placeholder(in context: Context) -> PegelWatchWidgetEntry { .placeholder }

    func snapshot(for configuration: SelectStationIntent,
                  in context: Context) async -> PegelWatchWidgetEntry {
        context.isPreview ? .placeholder : await buildEntry(for: configuration)
    }

    func timeline(for configuration: SelectStationIntent,
                  in context: Context) async -> Timeline<PegelWatchWidgetEntry> {
        let entry = await buildEntry(for: configuration)
        let next  = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        return Timeline(entries: [entry], policy: .after(next))
    }

    // MARK: - Private

    private func buildEntry(for config: SelectStationIntent) async -> PegelWatchWidgetEntry {
        let all     = await fetchAndUpdate(loadAllStationsFromDefaults())
        let pinned: WatchedStation?
        if let selectedID = config.station?.id {
            pinned = all.first { $0.id == selectedID } ?? all.first
        } else {
            pinned = all.first
        }
        let pinnedList: [WatchedStation] = pinned.map { [$0] } ?? []
        return PegelWatchWidgetEntry(date: .now, stations: pinnedList, allStations: all)
    }
}

// MARK: - Large Provider (not configurable — always shows full watchlist)

struct PegelWatchLargeProvider: TimelineProvider {

    func placeholder(in context: Context) -> PegelWatchWidgetEntry { .placeholder }

    func getSnapshot(in context: Context,
                     completion: @escaping (PegelWatchWidgetEntry) -> Void) {
        completion(.placeholder)
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<PegelWatchWidgetEntry>) -> Void) {
        Task {
            let all   = await fetchAndUpdate(loadAllStationsFromDefaults())
            let entry = PegelWatchWidgetEntry(date: .now, stations: all, allStations: all)
            let next  = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

// MARK: - Bundle

@main
struct PegelWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        PegelWatchWidget()          // small + medium, configurable
        PegelWatchLargeWidget()     // large, always shows full watchlist
        PegelWatchLiveActivityWidget()
        PegelWatchCriticalLiveActivityWidget()
    }
}

// MARK: - Small + Medium Widget (configurable)

struct PegelWatchWidget: Widget {
    let kind = "PegelWatchWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectStationIntent.self,
            provider: PegelWatchWidgetProvider()
        ) { entry in
            SmallMediumWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    ContainerRelativeShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    (entry.primary?.alarmLevel ?? .normal).color.opacity(
                                        entry.primary?.alarmLevel == .normal ? 0.04 : 0.10
                                    ),
                                    Color(.systemBackground)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .configurationDisplayName("PegelWatch")
        .description("Aktuelle Wasserstände im Blick.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Large Widget (not configurable — always shows full watchlist)

struct PegelWatchLargeWidget: Widget {
    let kind = "PegelWatchLargeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PegelWatchLargeProvider()) { entry in
            LargeWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("PegelWatch – Übersicht")
        .description("Alle beobachteten Pegelstationen auf einen Blick.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Small/Medium root view

struct SmallMediumWidgetView: View {
    let entry: PegelWatchWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:    AccessoryCircularView(entry: entry)
        case .accessoryRectangular: AccessoryRectangularView(entry: entry)
        case .accessoryInline:      AccessoryInlineView(entry: entry)
        case .systemMedium:         MediumWidgetView(entry: entry)
        default:                    SmallWidgetView(entry: entry)
        }
    }
}

// ────────────────────────────────────────────────────────────────
// MARK: - Small Widget
// ────────────────────────────────────────────────────────────────

struct SmallWidgetView: View {
    let entry: PegelWatchWidgetEntry

    var body: some View {
        if let station = entry.primary {
            VStack(alignment: .leading, spacing: 0) {
                Text(station.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(station.waterDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(station.lastValue.map { "\(Int($0))" } ?? "–")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(station.alarmLevel.color)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("cm")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let trend = station.trend, abs(trend) > 0.5 {
                        Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption.bold())
                            .foregroundStyle(trend > 0 ? .red.opacity(0.8) : .green.opacity(0.8))
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Circle()
                        .fill(station.alarmLevel.color)
                        .frame(width: 6, height: 6)
                    Text(station.alarmLevel.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if station.isStale {
                        Text("Veraltet")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if let updated = station.lastUpdated {
                        Text(updated, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "water.waves.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.quaternary)
                Text("Keine Station")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────
// MARK: - Medium Widget
// ────────────────────────────────────────────────────────────────

struct MediumWidgetView: View {
    let entry: PegelWatchWidgetEntry

    var body: some View {
        if let station = entry.primary {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(station.waterDisplayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(station.lastValue.map { "\(Int($0))" } ?? "–")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(station.alarmLevel.color)
                            .minimumScaleFactor(0.5)
                        Text("cm")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let trend = station.trend, abs(trend) > 0.5 {
                            Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                                .font(.caption.bold())
                                .foregroundStyle(trend > 0 ? .red.opacity(0.8) : .green.opacity(0.8))
                        }
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(station.alarmLevel.color)
                            .frame(width: 6, height: 6)
                        Text(station.alarmLevel.label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 8) {
                    if let threshold = station.alarmThreshold {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Schwelle")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("\(Int(threshold)) cm")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(station.alarmLevel.color)
                        }
                    }

                    Spacer()

                    if let updated = station.lastUpdated {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                            Text(updated, style: .relative)
                        }
                        .font(.caption2)
                        .foregroundStyle(station.isStale ? Color.orange : Color.secondary)
                    }

                    Text(HeichwaasserAPI.isLuxembourgStation(station.id) ? "Héichwaasser.lu" : "PegelOnline")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(14)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "water.waves.slash")
                    .font(.title2)
                    .foregroundStyle(.quaternary)
                Text("Öffne PegelWatch\num Stationen hinzuzufügen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

// ────────────────────────────────────────────────────────────────
// MARK: - Large Widget
// ────────────────────────────────────────────────────────────────

struct LargeWidgetView: View {
    let entry: PegelWatchWidgetEntry

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "water.waves")
                        .foregroundStyle(.blue)
                    Text("PegelWatch")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                if let updated = entry.stations.first?.lastUpdated {
                    Text(updated, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if entry.stations.isEmpty {
                Spacer()
                Text("Keine Stationen beobachtet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.stations.prefix(5).enumerated()), id: \.element.id) { idx, station in
                    if idx > 0 { Divider().padding(.leading, 16) }
                    LargeStationRow(station: station)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct LargeStationRow: View {
    let station: WatchedStation

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(station.alarmLevel.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(station.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(station.waterDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(station.lastValue.map { "\(Int($0))" } ?? "–")
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(station.alarmLevel == .normal ? .primary : station.alarmLevel.color)
                if let trend = station.trend, abs(trend) > 0.5 {
                    Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                        .font(.caption2.bold())
                        .foregroundStyle(trend > 0 ? .red.opacity(0.8) : .green.opacity(0.8))
                }
                Text("cm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// ────────────────────────────────────────────────────────────────
// MARK: - Accessory Circular (Lock Screen Gauge)
// ────────────────────────────────────────────────────────────────

private struct AccessoryCircularView: View {
    let entry: PegelWatchWidgetEntry

    var body: some View {
        if let station = entry.primary {
            if let value = station.lastValue, let threshold = station.alarmThreshold, threshold > 0 {
                Gauge(value: value, in: 0...threshold * 1.5) {
                    Image(systemName: "water.waves")
                } currentValueLabel: {
                    Text("\(Int(value))")
                        .font(.system(.body, design: .rounded).bold())
                } minimumValueLabel: {
                    Text("0")
                        .font(.system(.caption2))
                } maximumValueLabel: {
                    Text("\(Int(threshold))")
                        .font(.system(.caption2))
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
            } else {
                VStack(spacing: 1) {
                    Image(systemName: "water.waves")
                        .font(.caption)
                        .widgetAccentable()
                    Text(station.lastValue.map { "\(Int($0))" } ?? "–")
                        .font(.system(.title3, design: .rounded).bold())
                    Text("cm")
                        .font(.system(.caption2))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Image(systemName: "water.waves.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

// ────────────────────────────────────────────────────────────────
// MARK: - Accessory Rectangular (Lock Screen Detail)
// ────────────────────────────────────────────────────────────────

private struct AccessoryRectangularView: View {
    let entry: PegelWatchWidgetEntry

    var body: some View {
        if let station = entry.primary {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "water.waves")
                        .font(.caption2)
                        .widgetAccentable()
                    Text(station.displayName)
                        .font(.headline)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(station.lastValue.map { "\(Int($0)) cm" } ?? "– cm")
                        .font(.system(.body, design: .rounded).bold())

                    if let trend = station.trend, abs(trend) > 0.5 {
                        Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption2.bold())
                    }

                    Spacer()

                    Text(station.waterDisplayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let threshold = station.alarmThreshold, let value = station.lastValue {
                    ProgressView(value: min(value, threshold * 1.5), total: threshold * 1.5)
                        .tint(station.alarmLevel == .normal ? .green : station.alarmLevel.color)
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "water.waves.slash")
                    .font(.caption)
                Text("Keine Station")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────
// MARK: - Accessory Inline (Lock Screen Compact)
// ────────────────────────────────────────────────────────────────

private struct AccessoryInlineView: View {
    let entry: PegelWatchWidgetEntry

    var body: some View {
        if let station = entry.primary {
            HStack(spacing: 4) {
                Image(systemName: "water.waves")
                if let value = station.lastValue {
                    if let trend = station.trend, abs(trend) > 0.5 {
                        Text("\(station.displayName) \(Int(value)) cm \(trend > 0 ? "↑" : "↓")")
                    } else {
                        Text("\(station.displayName) \(Int(value)) cm")
                    }
                } else {
                    Text(station.displayName)
                }
            }
        } else {
            Text("PegelWatch")
        }
    }
}

// MARK: - Previews

#Preview("Small – Normal", as: .systemSmall) {
    PegelWatchWidget()
} timeline: {
    PegelWatchWidgetEntry.placeholder
}

#Preview("Small – Alarming", as: .systemSmall) {
    PegelWatchWidget()
} timeline: {
    PegelWatchWidgetEntry(date: .now, stations: [.previewAlarming], allStations: [.preview, .previewAlarming])
}

#Preview("Medium", as: .systemMedium) {
    PegelWatchWidget()
} timeline: {
    PegelWatchWidgetEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    PegelWatchLargeWidget()
} timeline: {
    PegelWatchWidgetEntry.placeholder
}

#Preview("Accessory Circular", as: .accessoryCircular) {
    PegelWatchWidget()
} timeline: {
    PegelWatchWidgetEntry.placeholder
}

#Preview("Accessory Rectangular", as: .accessoryRectangular) {
    PegelWatchWidget()
} timeline: {
    PegelWatchWidgetEntry.placeholder
}

#Preview("Accessory Inline", as: .accessoryInline) {
    PegelWatchWidget()
} timeline: {
    PegelWatchWidgetEntry.placeholder
}
