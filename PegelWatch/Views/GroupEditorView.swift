import SwiftUI

// MARK: - Group Manager Sheet

struct GroupManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = StationStore.shared
    @State private var groupToEdit: StationGroup?
    @State private var showAddGroup = false

    var body: some View {
        NavigationStack {
            List {
                if store.groups.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Gruppen", systemImage: "folder")
                    } description: {
                        Text("Erstelle eine Gruppe, um Stationen zu organisieren.")
                    }
                } else {
                    ForEach(store.groups) { group in
                        let stationCount = group.stationIDs.count
                        HStack(spacing: 14) {
                            Image(systemName: group.icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name).font(.headline)
                                Text("\(stationCount) Station\(stationCount == 1 ? "" : "en")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { groupToEdit = group } label: {
                                Image(systemName: "pencil.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            store.removeGroup(id: store.groups[idx].id)
                        }
                    }
                }
            }
            .navigationTitle("Gruppen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddGroup = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddGroup) {
                GroupEditorView { group in store.addGroup(group) }
            }
            .sheet(item: $groupToEdit) { group in
                GroupEditorView(existing: group) { updated in store.updateGroup(updated) }
            }
        }
    }
}

// MARK: - Group Editor View

struct GroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = StationStore.shared

    var existing: StationGroup?
    var onSave: (StationGroup) -> Void

    @State private var name: String = ""
    @State private var icon: String = "pin"
    @State private var selectedIDs: Set<String> = []

    static let availableIcons = [
        "pin", "star", "heart", "flag", "bookmark",
        "house", "ferry.fill", "figure.water.fitness",
        "cloud.rain.fill", "drop.fill", "water.waves",
        "map", "scope", "bell.fill", "exclamationmark.triangle.fill"
    ]

    init(existing: StationGroup? = nil, onSave: @escaping (StationGroup) -> Void) {
        self.existing = existing
        self.onSave = onSave
        if let g = existing {
            _name        = State(initialValue: g.name)
            _icon        = State(initialValue: g.icon)
            _selectedIDs = State(initialValue: Set(g.stationIDs))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("z.B. Rhein-Stationen", text: $name)
                }

                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 5), spacing: 14) {
                        ForEach(Self.availableIcons, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.title3)
                                .foregroundStyle(icon == symbol ? .white : .primary)
                                .frame(width: 44, height: 44)
                                .background(
                                    icon == symbol ? Color.accentColor : Color(.systemGray5),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .onTapGesture { icon = symbol }
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    if store.watchedStations.isEmpty {
                        Text("Noch keine Stationen auf der Merkliste.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(store.watchedStations) { station in
                            Button {
                                if selectedIDs.contains(station.id) {
                                    selectedIDs.remove(station.id)
                                } else {
                                    selectedIDs.insert(station.id)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(station.displayShortname)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text(station.waterDisplayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: selectedIDs.contains(station.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedIDs.contains(station.id)
                                                         ? Color.accentColor : Color.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Stationen (\(selectedIDs.count) ausgewählt)")
                }
            }
            .navigationTitle(existing == nil ? "Gruppe erstellen" : "Gruppe bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        var group = existing ?? StationGroup(name: name, icon: icon)
                        group.name = name.trimmingCharacters(in: .whitespaces)
                        group.icon = icon
                        group.stationIDs = Array(selectedIDs)
                        onSave(group)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    GroupManagerSheet();
}
