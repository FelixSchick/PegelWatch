import SwiftUI

struct StationRowView: View {

    let station: WatchedStation

    private var isAlarming: Bool {
        !station.noDataAvailable && station.alarmLevel != .normal
    }

    var body: some View {
        HStack(spacing: 0) {
            // Colored accent strip for alarming states
            RoundedRectangle(cornerRadius: 3)
                .fill(isAlarming ? station.alarmLevel.color : Color.clear)
                .frame(width: 4)
                .padding(.vertical, 4)
                .padding(.trailing, 12)

            alarmIndicator
                .padding(.trailing, 12)

            info
            Spacer()
            levelDisplay
        }
        .padding(.vertical, 8)
        .background {
            if isAlarming {
                RoundedRectangle(cornerRadius: 10)
                    .fill(station.alarmLevel.color.opacity(0.06))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: station.alarmLevel)
    }

    // MARK: - Subviews

    private var alarmIndicator: some View {
        ZStack {
            Circle()
                .fill(station.noDataAvailable
                      ? Color.gray.opacity(0.12)
                      : station.alarmLevel.color.opacity(isAlarming ? 0.2 : 0.12))
                .frame(width: 38, height: 38)
            Image(systemName: station.noDataAvailable
                  ? "antenna.radiowaves.left.and.right.slash"
                  : station.alarmLevel.systemImage)
                .foregroundStyle(station.noDataAvailable ? .gray : station.alarmLevel.color)
                .font(.system(size: 16, weight: .semibold))
                .symbolEffect(.pulse, isActive: station.alarmLevel == .critical)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(station.displayShortname)
                    .font(.headline)
                if station.isAlarmMuted {
                    Image(systemName: "bell.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 4) {
                Text(station.waterDisplayName)
                if let km = station.km {
                    Text("·").foregroundStyle(.tertiary)
                    Text("km \(Int(km))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var levelDisplay: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if station.noDataAvailable {
                Label("Keine Daten", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            } else if let value = station.lastValue {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(value)) cm")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(isAlarming ? station.alarmLevel.color : .primary)
                        .contentTransition(.numericText())
                    trendArrow
                }

                if let threshold = station.alarmThreshold {
                    Text("/ \(Int(threshold)) cm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let updated = station.lastUpdated {
                    Text(updated, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(station.isStale ? .orange : .accentColor)
                }
            } else {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
    }

    @ViewBuilder
    private var trendArrow: some View {
        if let trend = station.trend {
            if trend > 0.5 {
                Image(systemName: "arrow.up")
                    .font(.caption2.bold())
                    .foregroundStyle(.red.opacity(0.8))
            } else if trend < -0.5 {
                Image(systemName: "arrow.down")
                    .font(.caption2.bold())
                    .foregroundStyle(.green.opacity(0.8))
            }
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
