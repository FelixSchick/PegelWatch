import Foundation

struct StationGroup: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var icon: String = "pin"
    var stationIDs: [String] = []
}
