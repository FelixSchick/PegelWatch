import Foundation
import Observation

@Observable
class SnapshotStore {
    static let shared = SnapshotStore()

    var snapshots: [SavedSnapshot] = []

    private let appGroup   = "group.de.felixschick.pegelwatch"
    private let storageKey = "de.felixschick.pegelwatch.saved_snapshots"

    init() { load() }

    func save(_ snapshot: SavedSnapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        snapshots.insert(snapshot, at: 0)
        persist()
    }

    func delete(id: UUID) {
        snapshots.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data    = UserDefaults(suiteName: appGroup)?.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedSnapshot].self, from: data)
        else { return }
        snapshots = decoded
    }
}
