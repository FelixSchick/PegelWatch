import Foundation

/// Generates temp-file CSVs for sharing via ShareLink.
///
/// Uses semicolon separators — the German default for Excel/Numbers, which
/// interpret comma-separated files with locale-decimal ambiguity.
enum CSVExporter {

    /// Alarm-Historie einer Station als CSV.
    static func alarmHistory(for station: WatchedStation) -> URL? {
        let events = station.alarmHistory.sorted { $0.triggeredAt > $1.triggeredAt }
        guard !events.isEmpty else { return nil }

        var rows: [String] = [
            "Zeitpunkt;Ereignis;Pegel (cm);Schwelle (cm);Station;Gewässer"
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for event in events {
            let kind = event.kind == .triggered ? "Alarm ausgelöst" : "Entspannt"
            rows.append([
                formatter.string(from: event.triggeredAt),
                kind,
                String(Int(event.level)),
                String(Int(event.threshold)),
                escape(station.displayName),
                escape(station.waterDisplayName)
            ].joined(separator: ";"))
        }

        return write(rows: rows, name: "Alarmverlauf-\(safeName(station.displayName))")
    }

    /// Level-Verlauf (Wasserstand über Zeit) als CSV.
    static func levelHistory(
        for station: WatchedStation,
        history: [(timestamp: Date, value: Double)]
    ) -> URL? {
        guard !history.isEmpty else { return nil }

        var rows: [String] = ["Zeitpunkt;Pegel (cm);Station;Gewässer"]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for point in history.sorted(by: { $0.timestamp < $1.timestamp }) {
            rows.append([
                formatter.string(from: point.timestamp),
                String(format: "%.1f", point.value),
                escape(station.displayName),
                escape(station.waterDisplayName)
            ].joined(separator: ";"))
        }

        return write(rows: rows, name: "Verlauf-\(safeName(station.displayName))")
    }

    // MARK: - Helpers

    private static func write(rows: [String], name: String) -> URL? {
        let csv = rows.joined(separator: "\n")
        // BOM sorgt in Excel für korrektes UTF-8-Rendering von Umlauten.
        let bom = "\u{FEFF}"
        let content = bom + csv
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).csv")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ value: String) -> String {
        if value.contains(";") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private static func safeName(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "-")
             .replacingOccurrences(of: ":", with: "-")
             .replacingOccurrences(of: " ", with: "_")
    }
}
