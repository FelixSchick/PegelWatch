import SwiftUI
import Charts

/// Detail-Ansicht auf der Watch — bewusst schlank gehalten:
/// aktueller Wert, Trend, kleine Sparkline, Schwelle.
struct WatchStationDetailView: View {
    let station: WatchedStation
    @State private var history: [(timestamp: Date, value: Double)] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                sparkline
                thresholdRow
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle(station.displayShortname)
        .task { await loadHistory() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(station.lastValue.map { "\(Int($0))" } ?? "–")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(station.alarmLevel.color)
                Text("cm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let trend = station.trend, abs(trend) > 0.5 {
                    Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                        .font(.caption.bold())
                        .foregroundStyle(trend > 0 ? .red : .green)
                }
            }
            Text(station.waterDisplayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sparkline: some View {
        if history.count >= 2 {
            Chart {
                ForEach(history, id: \.timestamp) { point in
                    LineMark(x: .value("Zeit", point.timestamp),
                             y: .value("Pegel", point.value))
                        .foregroundStyle(station.alarmLevel.color)
                        .interpolationMethod(.catmullRom)
                }
                if let threshold = station.alarmThreshold {
                    RuleMark(y: .value("Schwelle", threshold))
                        .foregroundStyle(.red.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 60)
        } else if isLoading {
            ProgressView().frame(height: 60)
        }
    }

    @ViewBuilder
    private var thresholdRow: some View {
        if let threshold = station.alarmThreshold {
            HStack {
                Image(systemName: "bell")
                    .font(.caption2)
                Text("Schwelle: \(Int(threshold)) cm")
                    .font(.caption2)
                Spacer()
                Text(station.alarmLevel.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(station.alarmLevel.color)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        history = (try? await LevelDataProvider.history(for: station.id, days: 1)) ?? []
    }
}
