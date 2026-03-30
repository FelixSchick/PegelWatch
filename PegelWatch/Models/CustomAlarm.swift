//
//  CustomAlarm.swift
//  PegelWatch
//
//  Created by Felix Schick on 30.03.26.
//


import SwiftUI

/// A user-defined alarm level with a custom name, threshold, and color.
struct CustomAlarm: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String           // e.g. "Bootsanleger gesperrt"
    var threshold: Double      // cm value that triggers this alarm
    var colorHex: String       // stored as hex so it's Codable
    var notificationsEnabled: Bool = true

    // MARK: - Helpers

    var color: Color { Color(hex: colorHex) ?? .blue }

    /// Predefined palette the user can pick from
    static let palette: [(name: String, hex: String)] = [
        ("Blau",   "#0A84FF"),
        ("Lila",   "#BF5AF2"),
        ("Türkis", "#32ADE6"),
        ("Grün",   "#30D158"),
        ("Gelb",   "#FFD60A"),
        ("Orange", "#FF9F0A"),
        ("Rot",    "#FF453A"),
    ]
}

// Hex ↔ Color helper (add once to your project)
extension Color {
    init?(hex: String) {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}