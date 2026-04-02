//
//  AlarmEvent.swift
//  PegelWatch
//
//  Created by Felix Schick on 31.03.26.
//


import Foundation

/// A single recorded alarm crossing stored in the station's history.
struct AlarmEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// When the alarm fired
    var triggeredAt: Date
    /// Alarm level after fired
    var alarmLevel: AlarmLevel?
    /// Water level at the moment of triggering
    var level: Double
    /// The threshold that was crossed
    var threshold: Double
    /// Human-readable label, e.g. "Alarm" or a custom alarm name
    var label: String
    /// Whether this was a rise above or recovery below the threshold
    var kind: Kind

    enum Kind: String, Codable {
        case triggered  // level crossed threshold upward
        case recovered  // level dropped back below threshold
    }
}
