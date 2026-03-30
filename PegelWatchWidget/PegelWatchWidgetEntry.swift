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

// MARK: - Provider
struct PegelWatchWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = SelectStationIntent

    func placeholder(in context: Context) -> PegelWatchWidgetEntry { .placeholder }

    func snapshot(for configuration: SelectStationIntent,
                  in context: Context) async -> PegelWatchWidgetEntry {
        context.isPreview ? .placeholder : buildEntry(for: configuration)
    }

    func timeline(for configuration: SelectStationIntent,
                  in context: Context) async -> Timeline<PegelWatchWidgetEntry> {
        let entry = buildEntry(for: configuration)
        let next  = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date)!
        return Timeline(entries: [entry], policy: .after(next))
    }

    // MARK: - Private

    private func buildEntry(for config: SelectStationIntent) -> PegelWatchWidgetEntry {
        let all = loadAllStations()

        // Resolve the chosen entity ID → WatchedStation, fall back to first
        let pinned: WatchedStation?
        if let selectedID = config.station?.id {
            pinned = all.first { $0.id == selectedID } ?? all.first
        } else {
            pinned = all.first
        }

        return PegelWatchWidgetEntry(
            date: .now,
            stations: pinned.map { [$0] } ?? [],
            allStations: all
        )
    }

    private func loadAllStations() -> [WatchedStation] {
        let defaults = UserDefaults(suiteName: "group.de.felixschick.pegelwatch") ?? .standard
        guard
            let data    = defaults.data(forKey: "de.felixschick.pegelwatch.watched_stations"),
            let decoded = try? JSONDecoder().decode([WatchedStation].self, from: data)
        else { return [] }
        return decoded
    }
}

// MARK: - Bundle

@main
struct PegelWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        PegelWatchWidget()
        PegelWatchLiveActivityWidget()        // standard monitoring
        PegelWatchCriticalLiveActivityWidget()
    }
}

// MARK: - Widget Declaration

struct PegelWatchWidget: Widget {
    let kind = "PegelWatchWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectStationIntent.self,
            provider: PegelWatchWidgetProvider()
        ) { entry in
            PegelWatchWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("PegelWatch")
        .description("Aktuelle Wasserstände im Blick.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Root View (dispatches by family)

struct PegelWatchWidgetView: View {
    let entry: PegelWatchWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(entry: entry)
        case .systemMedium: MediumWidgetView(entry: entry)
        case .systemLarge:  LargeWidgetView(entry: entry)
        default:            SmallWidgetView(entry: entry)
        }
    }
}

// ────────────────────────────────────────────────────────────────
// MARK: - Small Widget
// Shows the primary (first) station: hero number + alarm badge
// ────────────────────────────────────────────────────────────────

struct SmallWidgetView: View {
    let entry: PegelWatchWidgetEntry

    var body: some View {
        if let station = entry.primary {
            filledView(station: station)
        } else {
            emptyView
        }
    }

    private func filledView(station: WatchedStation) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "water.waves")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(station.waterDisplayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // ── Hero level ──────────────────────────────
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(station.lastValue.map { "\(Int($0))" } ?? "–")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(station.alarmLevel.color)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("cm")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }

            // ── Station name ────────────────────────────
            Text(station.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 6)

            // ── Alarm badge ─────────────────────────────
            alarmBadge(station: station)

            // ── Staleness dot ───────────────────────────
            if station.isStale {
                HStack(spacing: 3) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 5, height: 5)
                    Text("Veraltet")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
    }

    private var emptyView: some View {
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

// ────────────────────────────────────────────────────────────────
// MARK: - Medium Widget
// Up to 3 station rows
// ────────────────────────────────────────────────────────────────

struct MediumDetailWidgetView: View {
    let station: WatchedStation

    private var fillFraction: Double {
        guard let v = station.lastValue, let t = station.alarmThreshold, t > 0
        else { return 0 }
        return min(v / (t * 1.5), 1.0)
    }

    var body: some View {
        HStack(spacing: 16) {

            // Left: big level number
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "water.waves")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text(station.waterDisplayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(station.lastValue.map { "\(Int($0))" } ?? "–")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(station.alarmLevel.color)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("cm")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }

                Text(station.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }

            Divider()

            // Right: threshold progress + alarm badge + updated
            VStack(alignment: .leading, spacing: 8) {
                Label(station.alarmLevel.label, systemImage: station.alarmLevel.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(station.alarmLevel.color)

                if station.alarmThreshold != nil {
                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(station.alarmLevel.color)
                                    .frame(width: geo.size.width * fillFraction, height: 6)
                            }
                        }
                        .frame(height: 6)

                        HStack {
                            Text("0")
                            Spacer()
                            if let t = station.alarmThreshold {
                                Text("Schwelle \(Int(t)) cm")
                                    .foregroundStyle(station.alarmLevel.color)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if let updated = station.lastUpdated {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                        Text(updated, style: .relative)
                    }
                    .font(.caption2)
                    .foregroundStyle(station.isStale ? .orange : .secondary)
                }
            }
        }
        .padding(14)
    }
}

private struct MediumStationRow: View {
    let station: WatchedStation

    var body: some View {
        HStack(spacing: 10) {

            // Alarm indicator circle
            ZStack {
                Circle()
                    .fill(station.alarmLevel.color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: station.alarmLevel.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(station.alarmLevel.color)
            }

            // Name + water
            VStack(alignment: .leading, spacing: 2) {
                Text(station.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(station.waterDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Level + threshold
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(station.lastValue.map { "\(Int($0))" } ?? "–")
                        .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(station.alarmLevel == .normal ? .primary : station.alarmLevel.color)
                    Text("cm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let threshold = station.alarmThreshold {
                    Text("/ \(Int(threshold)) cm")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MediumEmptyView: View {
    var body: some View {
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

struct MediumWidgetView: View {
    let entry: PegelWatchWidgetEntry

    var body: some View {
        if let pinned = entry.primary {
            // Single-station detail view
            MediumDetailWidgetView(station: pinned)
        } else {
            MediumEmptyView()
        }
    }
}

// ────────────────────────────────────────────────────────────────
// MARK: - Large Widget
// Up to 5 stations + threshold fill bar each
// ────────────────────────────────────────────────────────────────

struct LargeWidgetView: View {
    let entry: PegelWatchWidgetEntry

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "water.waves")
                    .foregroundStyle(.blue)
                Text("PegelWatch")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let updated = entry.stations.first?.lastUpdated {
                    Text(updated, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if entry.stations.isEmpty {
                Spacer()
                Text("Keine Stationen beobachtet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entry.stations.prefix(5).enumerated()), id: \.element.id) { idx, station in
                        if idx > 0 { Divider().padding(.leading, 16) }
                        LargeStationRow(station: station)
                    }
                }
            }
        }
    }
}

private struct LargeStationRow: View {
    let station: WatchedStation

    private var fillFraction: Double {
        guard let value = station.lastValue,
              let threshold = station.alarmThreshold,
              threshold > 0
        else { return 0 }
        return min(value / (threshold * 1.5), 1.0)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(station.alarmLevel.color.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: station.alarmLevel.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(station.alarmLevel.color)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(station.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(station.waterDisplayName + (station.km.map { " · km \(Int($0))" } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(station.lastValue.map { "\(Int($0))" } ?? "–")
                            .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(station.alarmLevel == .normal ? .primary : station.alarmLevel.color)
                        Text("cm")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(station.alarmLevel.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(station.alarmLevel.color)
                }
            }

            // Fill bar toward threshold
            if station.alarmThreshold != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(station.alarmLevel.color)
                            .frame(width: geo.size.width * fillFraction, height: 4)
                            .animation(.easeOut(duration: 0.6), value: fillFraction)
                    }
                }
                .frame(height: 4)
                .padding(.leading, 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Shared Helper

private func alarmBadge(station: WatchedStation) -> some View {
    HStack(spacing: 4) {
        Image(systemName: station.alarmLevel.systemImage)
            .font(.caption2.weight(.semibold))
        Text(station.alarmLevel.label)
            .font(.caption2.weight(.semibold))
    }
    .foregroundStyle(station.alarmLevel.color)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(station.alarmLevel.color.opacity(0.12), in: Capsule())
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
    PegelWatchWidget()
} timeline: {
    PegelWatchWidgetEntry.placeholder
}
