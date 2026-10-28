import SwiftUI

struct StationRowView: View {

    let station: WatchedStation

    private var isAlarming: Bool {
        !station.noDataAvailable && station.alarmLevel != .normal
    }

    var body: some View {
        HStack(spacing: 12) {
            alarmIndicator
            info
            Spacer(minLength: 8)
            levelDisplay
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.25), value: station.alarmLevel)
        // VoiceOver: eine zusammenhängende Ansage statt vieler Einzel-Elemente
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = [station.displayShortname, station.waterDisplayName]
        if station.noDataAvailable {
            parts.append("Keine Daten verfügbar")
        } else if let value = station.lastValue {
            parts.append("\(Int(value)) Zentimeter")
            parts.append(station.alarmLevel.label)
            if let rate = station.riseRateCmPerHour, abs(rate) >= 1 {
                parts.append(String(format: "%+.0f Zentimeter pro Stunde", rate))
            } else if let trend = station.trend, abs(trend) > 0.5 {
                parts.append(trend > 0 ? "steigend" : "fallend")
            }
        }
        if station.isAlarmMuted {
            parts.append("Alarme stummgeschaltet")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Subviews

    /// Statussymbol: Farbe *und* Form tragen die Alarmstufe, damit sie auch
    /// ohne Farbwahrnehmung unterscheidbar bleibt.
    private var alarmIndicator: some View {
        Image(systemName: station.noDataAvailable
              ? "antenna.radiowaves.left.and.right.slash"
              : station.alarmLevel.systemImage)
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(station.noDataAvailable ? .secondary : station.alarmLevel.color)
            // Einmaliges Hüpfen beim Stufenwechsel statt Dauerpulsieren in der Liste
            .symbolEffect(.bounce, value: station.alarmLevel)
            .frame(width: 32)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(station.displayShortname)
                    .font(.headline)
                    .lineLimit(1)
                if station.isAlarmMuted {
                    Image(systemName: "bell.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                // Alarmstufe als Text, nicht nur als Farbe des Symbols
                if isAlarming {
                    Text(station.alarmLevel.label)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("·")
                }
                Text(station.waterDisplayName)
                if let km = station.km {
                    Text("· km \(Int(km))")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var levelDisplay: some View {
        if station.noDataAvailable {
            Text("Keine Daten")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if let value = station.lastValue {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    trendArrow
                    Text("\(Int(value))")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        // Orange/Gelb erreichen als Textfarbe keinen ausreichenden
                        // Kontrast; die Alarmfarbe trägt das Symbol links.
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text("cm")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                detailLine
            }
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    /// Zweite Zeile rechts: Steig-/Fallrate, sonst Alter des Messwerts.
    @ViewBuilder
    private var detailLine: some View {
        if station.isStale, let updated = station.lastUpdated {
            Label {
                RelativeTimeText(date: updated)
            } icon: {
                Image(systemName: "clock.badge.exclamationmark")
            }
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(.orange)
        } else if let rate = station.riseRateCmPerHour, abs(rate) >= 1 {
            Text(String(format: "%+.0f cm/h", rate))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        } else if let updated = station.lastUpdated {
            RelativeTimeText(date: updated)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trendArrow: some View {
        if let trend = station.trend, abs(trend) > 0.5 {
            Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption.weight(.bold))
                // Rot/Grün bleiben den Alarmstufen vorbehalten
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    List {
        StationRowView(station: .preview)
        StationRowView(station: .previewAlarming)
        StationRowView(station: .previewNoData)
    }
}
