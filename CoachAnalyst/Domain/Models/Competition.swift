import Foundation

/// A StatsBomb competition season (one row of the open-data `competitions.json`).
/// `competitionID` + `seasonID` together identify a season of a competition.
struct Competition: Identifiable, Hashable, Codable, Sendable {
    let competitionID: Int
    let seasonID: Int
    let name: String
    let country: String
    let gender: String
    let seasonName: String

    var id: String { "\(competitionID)-\(seasonID)" }
    var displayName: String { "\(name) · \(seasonName)" }

    var isWomen: Bool { gender.lowercased().contains("women") || gender.lowercased() == "female" }
}
