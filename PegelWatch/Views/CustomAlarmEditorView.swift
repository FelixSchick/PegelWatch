//
//  CustomAlarmEditorView.swift
//  PegelWatch
//
//  Created by Felix Schick on 30.03.26.
//


import SwiftUI

struct CustomAlarmEditorView: View {
    @Environment(\.dismiss) private var dismiss

    var stationID: String
    var existing: CustomAlarm?          // nil = create new
    var onSave: (CustomAlarm) -> Void
    /// Nur beim Bearbeiten: entfernt den Alarm.
    var onDelete: (() -> Void)?

    @State private var name: String = ""
    @State private var thresholdText: String = "200"

    /// Gültige Schwelle aus dem Eingabefeld, sonst nil (Speichern deaktiviert).
    private var threshold: Double? {
        Double(thresholdText).flatMap { $0 > 0 ? $0 : nil }
    }
    @State private var selectedHex: String = CustomAlarm.palette[0].hex
    @State private var notificationsEnabled: Bool = true
    @State private var selectedSoundID: String?
    @State private var previewPlayer = SoundPreviewPlayer.shared

    /// Der Ton, den die Vorschau abspielen würde (Alarm-eigener oder globaler).
    private var resolvedPreviewSound: AlarmSound {
        AlarmSound(idOrDefault: selectedSoundID
            ?? AlarmSoundSettings.shared.alarmSound.rawValue)
    }

    init(stationID: String, existing: CustomAlarm? = nil,
         onSave: @escaping (CustomAlarm) -> Void, onDelete: (() -> Void)? = nil) {
        self.stationID = stationID
        self.existing  = existing
        self.onSave    = onSave
        self.onDelete  = onDelete
        if let a = existing {
            _name                 = State(initialValue: a.name)
            _thresholdText        = State(initialValue: "\(Int(a.threshold))")
            _selectedHex          = State(initialValue: a.colorHex)
            _notificationsEnabled = State(initialValue: a.notificationsEnabled)
            _selectedSoundID      = State(initialValue: a.soundID)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("z.B. Bootsanleger gesperrt", text: $name)
                }

                Section {
                    HStack {
                        Text("Schwelle")
                        Spacer()
                        TextField("cm", text: $thresholdText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("cm")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Alarmschwelle", systemImage: "ruler")
                }

                Section("Farbe") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 7), spacing: 12) {
                        ForEach(CustomAlarm.palette, id: \.hex) { item in
                            Button {
                                selectedHex = item.hex
                            } label: {
                                // Auswahl als Ring statt weißem Haken – der wäre auf
                                // Gelb/Türkis/Grün kaum sichtbar.
                                Circle()
                                    .fill(Color(hex: item.hex) ?? .blue)
                                    .frame(width: 32, height: 32)
                                    .padding(4)
                                    .overlay {
                                        if selectedHex == item.hex {
                                            Circle().strokeBorder(.primary, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.name)
                            .accessibilityAddTraits(selectedHex == item.hex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Benachrichtigungen", isOn: $notificationsEnabled)

                    if notificationsEnabled {
                        HStack {
                            Picker("Alarmton", selection: $selectedSoundID) {
                                Text("Wie global eingestellt").tag(String?.none)
                                ForEach(AlarmSound.allCases) { sound in
                                    Text(sound.displayName).tag(String?.some(sound.rawValue))
                                }
                            }

                            Button {
                                previewPlayer.toggle(resolvedPreviewSound,
                                                     volume: AlarmSoundSettings.shared.criticalVolume)
                            } label: {
                                Image(systemName: previewPlayer.playingSound == resolvedPreviewSound
                                      ? "stop.circle.fill" : "play.circle")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Live preview
                Section("Vorschau") {
                    HStack {
                        Circle()
                            .fill(Color(hex: selectedHex) ?? .blue)
                            .frame(width: 10, height: 10)
                        Text(name.isEmpty ? "Mein Alarm" : name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(threshold.map { "\(Int($0)) cm" } ?? "–")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if existing != nil, let onDelete {
                    Section {
                        Button("Alarm löschen", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Alarm hinzufügen" : "Alarm bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { previewPlayer.stop() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard let threshold else { return }
                        var alarm = existing ?? CustomAlarm(
                            name: name, threshold: threshold, colorHex: selectedHex
                        )
                        alarm.name                 = name.trimmingCharacters(in: .whitespaces)
                        alarm.threshold            = threshold
                        alarm.colorHex             = selectedHex
                        alarm.notificationsEnabled = notificationsEnabled
                        alarm.soundID              = selectedSoundID
                        onSave(alarm)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || threshold == nil)
                }
            }
        }
    }
}