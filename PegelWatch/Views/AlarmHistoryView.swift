//
//  AlarmHistoryView.swift
//  PegelWatch
//
//  Created by Felix Schick on 31.03.26.
//


import SwiftUI

struct AlarmHistoryView: View {
    let station: WatchedStation
    @State private var store = StationStore.shared

    private var history: [AlarmEvent] {
        // Most recent first
        station.alarmHistory.sorted { $0.triggeredAt > $1.triggeredAt }
    }

    var body: some View {
        NavigationStack {
            if history.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Alarm-Verlauf")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        store.clearAlarmHistory(for: station.id)
                    } label: {
                        Label("Verlauf löschen", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - List

    private var list: some View {
        List(history) { event in
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(event.kind == .triggered ? Color.red.opacity(0.12) : Color.teal.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: event.kind == .triggered ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(event.kind == .triggered ? .red : .teal)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(event.kind == .triggered ? .red : .teal)

                    HStack(spacing: 6) {
                        Text("\(Int(event.level)) cm")
                            .font(.caption.weight(.medium).monospacedDigit())
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("Schwelle \(Int(event.threshold)) cm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(event.triggeredAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        + Text(" · ")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        + Text(event.triggeredAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Kein Verlauf", systemImage: "bell.slash")
        } description: {
            Text("Noch kein Alarm ausgelöst.")
        }
    }
}
