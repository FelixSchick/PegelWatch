import Foundation

// Matches the PegelOnline REST API response
// GET https://pegelonline.wsv.de/webservices/rest-api/v2/stations.json

struct Station: Identifiable, Codable, Hashable {
    let uuid: String
    let number: String
    let shortname: String
    let longname: String
    let km: Double?
    let agency: String
    let longitude: Double?
    let latitude: Double?
    let water: WaterInfo

    var id: String { uuid }

    var displayName: String {
        longname.isEmpty ? shortname : longname.capitalized
    }
}

struct WaterInfo: Codable, Hashable {
    let shortname: String
    let longname: String

    var displayName: String {
        longname.isEmpty ? shortname : longname.capitalized
    }
}

// MARK: - Measurement Models

/// Returned directly by /stations/{uuid}/W/currentmeasurement.json
struct CurrentMeasurement: Codable {
    let timestamp: String
    let value: Double
    let stateMnwMhw: String?
    let stateNswHsw: String?
}

struct APILevelMeasurement: Codable {
    let timestamp: Date
    let value: Double
}

// MARK: - Preview

extension Station {
    static let preview = Station(
        uuid: "3da9ddb7-a8dc-400e-8fe5-db2e9a347d90",
        number: "2300040",
        shortname: "KOBLENZ",
        longname: "KOBLENZ",
        km: 590.3,
        agency: "WSA MITTELRHEIN",
        longitude: 7.609,
        latitude: 50.35,
        water: WaterInfo(shortname: "RHEIN", longname: "RHEIN")
    )
}

extension APILevelMeasurement {
    static let previewHistory: [(timestamp: Date, value: Double)] = {
        let calendar = Calendar.current
        let now = Date()
        // Simulate 7 days of hourly readings with realistic river fluctuation
        return (0..<168).reversed().map { hoursAgo in
            let date = calendar.date(byAdding: .hour, value: -hoursAgo, to: now)!
            // Base level with a flood peak around 3 days ago
            let dayPhase = Double(hoursAgo) / 24.0
            let floodPeak = 80.0 * exp(-0.5 * pow((dayPhase - 3.5) / 1.2, 2))
            let diurnal = 8.0 * sin(Double(hoursAgo) * .pi / 12)  // tidal/daily rhythm
            let noise = Double.random(in: -3...3)
            let value = 180.0 + floodPeak + diurnal + noise
            return (timestamp: date, value: value)
        }
    }()
}
