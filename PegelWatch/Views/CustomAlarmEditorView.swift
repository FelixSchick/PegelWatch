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

    @State private var name: String = ""
    @State private var threshold: Double = 200
    @State private var thresholdText: String = "200"
    @State private var selectedHex: String = CustomAlarm.palette[0].hex
    @State private var notificationsEnabled: Bool = true
    @State private var selectedSoundID: String?
    @State private var previewPlayer = SoundPreviewPlayer.shared

    init(stationID: String, existing: CustomAlarm? = nil, onSave: @escaping (CustomAlarm) -> Void) {
        self.stationID = stationID
        self.existing  = existing
        self.onSave    = onSave
        if let a = existing {
            _name                 = State(initialValue: a.name)
            _threshold            = State(initialValue: a.threshold)
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
                            .frame(width: 80)
                            .onChange(of: thresholdText) {
                                if let v = Double(thresholdText) { threshold = v }
                            }
                        Text("cm")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Alarmschwelle", systemImage: "ruler")
                }

                Section("Farbe") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 7), spacing: 12) {
                        ForEach(CustomAlarm.palette, id: \.hex) { item in
                            Circle()
                                .fill(Color(hex: item.hex) ?? .blue)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if selectedHex == item.hex {
                                        Circle()
                                            .strokeBorder(.white, lineWidth: 2)
                                            .padding(2)
                                    }
                                }
                                .onTapGesture { selectedHex = item.hex }
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
                                let sound = AlarmSound(idOrDefault: selectedSoundID
                                    ?? AlarmSoundSettings.shared.alarmSound.rawValue)
                                previewPlayer.toggle(sound, volume: AlarmSoundSettings.shared.criticalVolume)
                            } label: {
                                Image(systemName: previewPlayer.playingSound != nil
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
                        Text("\(Int(threshold)) cm")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
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
                        var alarm = existing ?? CustomAlarm(
                            name: name, threshold: threshold, colorHex: selectedHex
                        )
                        alarm.name                 = name.isEmpty ? "Alarm" : name
                        alarm.threshold            = threshold
                        alarm.colorHex             = selectedHex
                        alarm.notificationsEnabled = notificationsEnabled
                        alarm.soundID              = selectedSoundID
                        onSave(alarm)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}