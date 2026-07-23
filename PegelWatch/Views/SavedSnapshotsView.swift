import SwiftUI

struct SavedSnapshotsView: View {
    @State private var store = SnapshotStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.snapshots.isEmpty {
                    emptyState
                } else {
                    snapshotList
                }
            }
            .navigationTitle("Gespeicherte Lageübersichten")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - List

    private var snapshotList: some View {
        List {
            ForEach(store.snapshots) { snapshot in
                NavigationLink(value: snapshot) {
                    snapshotRow(snapshot)
                }
            }
            .onDelete { indexSet in
                for idx in indexSet { store.delete(id: store.snapshots[idx].id) }
            }
        }
        .navigationDestination(for: SavedSnapshot.self) { snapshot in
            SnapshotPreviewView(snapshot: snapshot, isSavedAlready: true)
        }
    }

    private func snapshotRow(_ snapshot: SavedSnapshot) -> some View {
        let worst = worstAlarmLevel(in: snapshot)
        return VStack(alignment: .leading, spacing: 5) {
            Text(snapshot.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 6) {
                Label(
                    snapshot.createdAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("·").font(.caption).foregroundStyle(.tertiary)

                Label("\(snapshot.stations.count) Stationen", systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if worst != .normal {
                    Text("·").font(.caption).foregroundStyle(.tertiary)
                    Label(worst.label, systemImage: worst.systemImage)
                        .font(.caption.bold())
                        .foregroundStyle(severityColor(worst))
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Keine Lageübersichten", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Erstelle eine Lageübersicht über die Beobachtungsliste und speichere sie hier.")
        }
    }

    // MARK: - Helpers

    private func worstAlarmLevel(in snapshot: SavedSnapshot) -> AlarmLevel {
        let levels = snapshot.stations.map(\.alarmLevel)
        if levels.contains(.critical) { return .critical }
        if levels.contains(.danger)   { return .danger }
        if levels.contains(.warning)  { return .warning }
        return .normal
    }

    private func severityColor(_ level: AlarmLevel) -> Color {
        switch level {
        case .normal:   return Color(red: 0.13, green: 0.69, blue: 0.30)
        case .warning:  return Color(red: 0.80, green: 0.55, blue: 0.00)
        case .danger:   return Color(red: 0.90, green: 0.35, blue: 0.00)
        case .critical: return Color(red: 0.85, green: 0.10, blue: 0.10)
        }
    }
}

#Preview {
    SavedSnapshotsView()
}
