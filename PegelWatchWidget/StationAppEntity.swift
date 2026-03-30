//
//  StationAppEntity.swift
//  PegelWatch
//
//  Created by Felix Schick on 30.03.26.
//


import AppIntents
import Foundation

/// A single watched station exposed to the AppIntents system.
struct StationAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Pegelstation"

    static var defaultQuery = StationEntityQuery()

    var id: String          // UUID string
    var displayName: String // e.g. "Koblenz"
    var waterName: String   // e.g. "Rhein"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: "\(waterName)"
        )
    }
}