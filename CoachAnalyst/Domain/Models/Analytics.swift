import Foundation

/// Team-level metrics. The same shape is used for a single match (where
/// `matches == 1`) and for a season aggregate.
struct TeamMetrics: Codable, Hashable, Sendable {
    var matches: Int
    var possession: Double
    var passAccuracy: Double
    var passes: Double
    var progressivePasses: Double
    var finalThirdPasses: Double
    var boxEntries: Double
    var shots: Double
    var shotsOnTarget: Double
    var xg: Double
    var goals: Double
    var ppda: Double
    var pressures: Double
    var interceptions: Double
    var tackles: Double
    var highTurnovers: Double
    var xgFor: Double
    var recent: [TeamRecentMatch]
}

struct TeamRecentMatch: Codable, Hashable, Sendable, Identifiable {
    let opponent: String
    let home: Bool
    let goalsFor: Int
    let goalsAgainst: Int
    let xg: Double
    let date: String

    var id: String { "\(date)-\(opponent)" }
    var result: String {
        if goalsFor > goalsAgainst { return "W" }
        if goalsFor < goalsAgainst { return "L" }
        return "D"
    }
}

/// One side of a match analysis.
struct MatchSide: Codable, Hashable, Sendable {
    let team: Team
    let stats: TeamMetrics
    let players: [PlayerImpact]
}

struct PlayerImpact: Codable, Hashable, Sendable, Identifiable {
    let playerID: String
    let name: String
    let minutes: Int
    let goals: Int
    let assists: Int
    let xg: Double
    let keyPasses: Int
    let impact: Double

    var id: String { playerID }
}

struct ShotItem: Codable, Hashable, Sendable, Identifiable {
    let minute: Int
    let x: Double
    let y: Double
    let xg: Double
    let outcome: String
    let teamID: Int
    let player: String

    var id: String { "\(teamID)-\(minute)-\(Int(x * 10))-\(Int(y * 10))-\(player)" }
    var isGoal: Bool { outcome == "Goal" }
}

struct MomentumBucket: Codable, Hashable, Sendable, Identifiable {
    let minute: Int
    let home: Double
    let away: Double

    var id: Int { minute }
}

/// Full post-game analysis for a single match.
struct MatchAnalysis: Codable, Hashable, Sendable {
    let match: ScoutFixture
    let home: MatchSide
    let away: MatchSide
    let shots: [ShotItem]
    let momentum: [MomentumBucket]
}

/// Season analysis for a club — the basis for own-team and opponent reports.
struct TeamAnalysis: Codable, Hashable, Sendable {
    let team: Team
    let competition: Competition
    let stats: TeamMetrics
    let players: [PlayerMetricProfile]
    let fixtures: [ScoutFixture]
}

/// The coach's team, chosen from the scouting flow and used by the Matches tab.
struct OwnTeam: Codable, Hashable, Sendable {
    let competition: Competition
    let team: Team
}

/// Navigation value for opening a post-game report.
struct MatchRoute: Hashable {
    let competition: Competition
    let fixture: ScoutFixture
}

/// Navigation value for opening a team season report.
struct TeamAnalysisRoute: Hashable {
    let competition: Competition
    let team: Team
}
