//
//  SelectStationIntent.swift
//  PegelWatch
//
//  Created by Felix Schick on 30.03.26.
//


import AppIntents
import WidgetKit

struct SelectStationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Station auswählen"
    static var description = IntentDescription("Wähle die anzuzeigende Pegelstation.")

    // Single entity parameter → renders as a searchable dropdown in the widget editor
    @Parameter(title: "Station", optionsProvider: StationOptionsProvider())
    var station: StationAppEntity?
}

// MARK: - Options Provider (powers the dropdown + search)

private struct StationOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [StationAppEntity] {
        try await StationEntityQuery().suggestedEntities()
    }
}
