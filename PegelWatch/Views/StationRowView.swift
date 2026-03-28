import SwiftUI

struct StationRowView: View {

    let station: WatchedStation

    var body: some View {
        HStack(spacing: 14) {
            alarmIndicator
            info
            Spacer()
            levelDisplay
        }
        .padding(.vertical, 6)
    }

    // MARK: - Subviews

    private var alarmIndicator: some View {
        ZStack {
            Circle()
                .fill(station.alarmLevel.color.opacity(0.15))
                .frame(width: 36, height: 36)
            Image(systemName: station.alarmLevel.systemImage)
                .foregroundStyle(station.alarmLevel.color)
                .font(.system(size: 16, weight: .semibold))
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(station.shortname)
                .font(.headline)
            HStack(spacing: 4) {
                Text(station.waterDisplayName)
                if let km = station.km {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("km \(Int(km))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var levelDisplay: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let value = station.lastValue {
                Text("\(Int(value)) cm")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(station.alarmLevel == .normal ? .primary : station.alarmLevel.color)

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
}

#Preview {
    List {
        StationRowView(station: .preview)
        StationRowView(station: .previewAlarming)
    }
}
