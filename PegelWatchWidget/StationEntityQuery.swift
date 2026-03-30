//
//  StationEntityQuery.swift
//  PegelWatch
//
//  Created by Felix Schick on 30.03.26.
//


import AppIntents
import Foundation

struct StationEntityQuery: EntityQuery {

    // MARK: - Required

    /// Called when the user searches or the picker needs to show results.
    func entities(for identifiers: [String]) async throws -> [StationAppEntity] {
        loadAll().filter { identifiers.contains($0.id) }
    }

    // MARK: - Optional but important: fills the initial dropdown list

    func suggestedEntities() async throws -> [StationAppEntity] {
        loadAll()
    }

    // MARK: - Private

    private func loadAll() -> [StationAppEntity] {
        let defaults = UserDefaults(suiteName: "group.de.felixschick.pegelwatch") ?? .standard
        guard
            let data    = defaults.data(forKey: "de.felixschick.pegelwatch.watched_stations"),
            let decoded = try? JSONDecoder().decode([WatchedStation].self, from: data)
        else { return [] }

        return decoded.map {
            StationAppEntity(
                id: $0.id,
                displayName: $0.displayName,
                waterName: $0.waterDisplayName
            )
        }
    }
}