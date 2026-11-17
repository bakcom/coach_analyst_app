import Foundation

// MARK: - Position grouping

/// Coarse role used to (a) pick which metrics matter and (b) keep similarity
/// comparisons within like-for-like roles.
enum PositionGroup: String, CaseIterable, Codable, Hashable, Sendable {
    case goalkeeper = "Goalkeeper"
    case defender = "Defender"
    case midfielder = "Midfielder"
    case forward = "Forward"

    var short: String {
        switch self {
        case .goalkeeper: "GK"
        case .defender: "DEF"
        case .midfielder: "MID"
        case .forward: "FWD"
        }
    }

    /// Maps a StatsBomb position name (e.g. "Left Center Back", "Right Wing Back",
    /// "Center Attacking Midfield", "Right Wing", "Center Forward") onto a group.
    /// Order matters: wing-backs must resolve to defenders, wingers to forwards.
    static func from(positionName: String) -> PositionGroup {
        let n = positionName.lowercased()
        if n.contains("goalkeeper") { return .goalkeeper }
        if n.contains("back") { return .defender }
        if n.contains("midfield") { return .midfielder }
        if n.contains("wing") { return .forward }
        if n.contains("forward") || n.contains("striker") { return .forward }
        return .midfielder
    }
}

// MARK: - Raw aggregated counters

/// Raw (non-normalised) event counters for one player across a set of matches.
struct MetricTotals: Codable, Hashable, Sendable {
    var minutes: Double = 0
    var goals: Double = 0
    var xg: Double = 0
    var shots: Double = 0
    var assists: Double = 0
    var keyPasses: Double = 0
    var passesAttempted: Double = 0
    var passesCompleted: Double = 0
    var progressivePasses: Double = 0
    var finalThirdPasses: Double = 0
    var carries: Double = 0
    var progressiveCarries: Double = 0
    var dribblesCompleted: Double = 0
    var tacklesWon: Double = 0
    var interceptions: Double = 0
    var clearances: Double = 0
    var ballRecoveries: Double = 0
    var pressures: Double = 0
    var touchesInBox: Double = 0
    var saves: Double = 0

    static func + (lhs: MetricTotals, rhs: MetricTotals) -> MetricTotals {
        MetricTotals(
            minutes: lhs.minutes + rhs.minutes,
            goals: lhs.goals + rhs.goals,
            xg: lhs.xg + rhs.xg,
            shots: lhs.shots + rhs.shots,
            assists: lhs.assists + rhs.assists,
            keyPasses: lhs.keyPasses + rhs.keyPasses,
            passesAttempted: lhs.passesAttempted + rhs.passesAttempted,
            passesCompleted: lhs.passesCompleted + rhs.passesCompleted,
            progressivePasses: lhs.progressivePasses + rhs.progressivePasses,
            finalThirdPasses: lhs.finalThirdPasses + rhs.finalThirdPasses,
            carries: lhs.carries + rhs.carries,
            progressiveCarries: lhs.progressiveCarries + rhs.progressiveCarries,
            dribblesCompleted: lhs.dribblesCompleted + rhs.dribblesCompleted,
            tacklesWon: lhs.tacklesWon + rhs.tacklesWon,
            interceptions: lhs.interceptions + rhs.interceptions,
            clearances: lhs.clearances + rhs.clearances,
            ballRecoveries: lhs.ballRecoveries + rhs.ballRecoveries,
            pressures: lhs.pressures + rhs.pressures,
            touchesInBox: lhs.touchesInBox + rhs.touchesInBox,
            saves: lhs.saves + rhs.saves
        )
    }

    static func += (lhs: inout MetricTotals, rhs: MetricTotals) { lhs = lhs + rhs }
}

// MARK: - Metric definitions

/// The metrics the prototype compares on. Rate metrics are expressed per 90;
/// `passAccuracy` is a 0...1 ratio.
enum ScoutMetric: String, CaseIterable, Codable, Hashable, Sendable {
    case goals, xg, shots, assists, keyPasses
    case passesAttempted, passAccuracy, progressivePasses, finalThirdPasses
    case carries, progressiveCarries, dribblesCompleted
    case tacklesWon, interceptions, clearances, ballRecoveries, pressures
    case touchesInBox, saves

    var title: String {
        switch self {
        case .goals: "Goals"
        case .xg: "xG"
        case .shots: "Shots"
        case .assists: "Assists"
        case .keyPasses: "Key passes"
        case .passesAttempted: "Passes"
        case .passAccuracy: "Pass accuracy"
        case .progressivePasses: "Progressive passes"
        case .finalThirdPasses: "Final-third passes"
        case .carries: "Carries"
        case .progressiveCarries: "Progressive carries"
        case .dribblesCompleted: "Dribbles completed"
        case .tacklesWon: "Tackles won"
        case .interceptions: "Interceptions"
        case .clearances: "Clearances"
        case .ballRecoveries: "Ball recoveries"
        case .pressures: "Pressures"
        case .touchesInBox: "Touches in box"
        case .saves: "Saves"
        }
    }

    var isRatio: Bool { self == .passAccuracy }

    var unit: String { isRatio ? "%" : "p90" }

    /// Compact label for the radar axes.
    var shortTitle: String {
        switch self {
        case .goals: "Goals"
        case .xg: "xG"
        case .shots: "Shots"
        case .assists: "Assists"
        case .keyPasses: "KeyP"
        case .passesAttempted: "Passes"
        case .passAccuracy: "Pass%"
        case .progressivePasses: "PrgP"
        case .finalThirdPasses: "3rdP"
        case .carries: "Carry"
        case .progressiveCarries: "PrgC"
        case .dribblesCompleted: "Drib"
        case .tacklesWon: "Tkl"
        case .interceptions: "Int"
        case .clearances: "Clr"
        case .ballRecoveries: "Rec"
        case .pressures: "Press"
        case .touchesInBox: "Box"
        case .saves: "Saves"
        }
    }

    private func raw(_ t: MetricTotals) -> Double {
        switch self {
        case .goals: t.goals
        case .xg: t.xg
        case .shots: t.shots
        case .assists: t.assists
        case .keyPasses: t.keyPasses
        case .passesAttempted: t.passesAttempted
        case .passAccuracy: t.passesAttempted
        case .progressivePasses: t.progressivePasses
        case .finalThirdPasses: t.finalThirdPasses
        case .carries: t.carries
        case .progressiveCarries: t.progressiveCarries
        case .dribblesCompleted: t.dribblesCompleted
        case .tacklesWon: t.tacklesWon
        case .interceptions: t.interceptions
        case .clearances: t.clearances
        case .ballRecoveries: t.ballRecoveries
        case .pressures: t.pressures
        case .touchesInBox: t.touchesInBox
        case .saves: t.saves
        }
    }

    /// Value used for comparison and display.
    func value(of t: MetricTotals, minutes: Double) -> Double {
        if self == .passAccuracy {
            return t.passesAttempted > 0 ? t.passesCompleted / t.passesAttempted : 0
        }
        guard minutes > 0 else { return 0 }
        return (raw(t) / minutes) * 90
    }

    func display(_ value: Double) -> String {
        if isRatio { return "\(Int((value * 100).rounded()))%" }
        if self == .xg { return String(format: "%.2f", value) }
        return String(format: "%.1f", value)
    }

    /// The metrics that matter for a role. Similarity is only computed within a
    /// group, over this set.
    static func metrics(for group: PositionGroup) -> [ScoutMetric] {
        switch group {
        case .goalkeeper:
            return [.saves, .passAccuracy, .passesAttempted, .ballRecoveries]
        case .defender:
            return [.tacklesWon, .interceptions, .clearances, .ballRecoveries,
                    .passAccuracy, .progressivePasses, .pressures, .passesAttempted]
        case .midfielder:
            return [.passesAttempted, .passAccuracy, .progressivePasses, .finalThirdPasses,
                    .keyPasses, .carries, .progressiveCarries, .dribblesCompleted,
                    .interceptions, .pressures, .ballRecoveries]
        case .forward:
            return [.goals, .xg, .shots, .assists, .keyPasses,
                    .dribblesCompleted, .touchesInBox, .progressiveCarries, .pressures]
        }
    }
}

// MARK: - Player profile

/// A player's aggregated, position-tagged metric profile — the unit the
/// similarity engine compares.
struct PlayerMetricProfile: Identifiable, Hashable, Codable, Sendable {
    let playerID: String
    let name: String
    let teamName: String
    let competitionID: Int
    let competitionName: String
    let group: PositionGroup
    let primaryPosition: String
    var totals: MetricTotals

    var id: String { playerID }
    var minutes: Double { totals.minutes }

    func value(_ metric: ScoutMetric) -> Double { metric.value(of: totals, minutes: totals.minutes) }
    func display(_ metric: ScoutMetric) -> String { metric.display(value(metric)) }
}

/// A neighbour returned by the similarity engine.
struct SimilarPlayer: Identifiable, Hashable, Codable, Sendable {
    let profile: PlayerMetricProfile
    let score: Double // 0...100
    var id: String { profile.playerID }
}

/// One axis of a head-to-head comparison. Values are the raw metric values;
/// `*Normalized` are 0...1 percentile ranks within the pool population, used to
/// draw both players on the same radar.
struct MetricComparison: Identifiable, Hashable, Codable, Sendable {
    let metric: ScoutMetric
    let targetValue: Double
    let candidateValue: Double
    let targetNormalized: Double
    let candidateNormalized: Double
    let populationAverage: Double

    var id: ScoutMetric { metric }
    var higher: ComparisonSide { targetValue == candidateValue ? .tied : (targetValue > candidateValue ? .target : .candidate) }
}

enum ComparisonSide { case target, candidate, tied }

// MARK: - Fixtures & datasets

/// Navigation value for "browse the clubs in a competition".
struct ScoutTeamRoute: Hashable {
    let competition: Competition
    let team: Team
}

/// Navigation value for a head-to-head comparison between two players.
struct ScoutComparisonRoute: Hashable {
    let target: PlayerMetricProfile
    let candidate: PlayerMetricProfile
}

struct ScoutFixture: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let date: Date
    let home: Team
    let away: Team
    let homeScore: Int
    let awayScore: Int

    func scoreLine() -> String { "\(homeScore) – \(awayScore)" }
    func opponent(of team: Team) -> Team { team.id == home.id ? away : home }
}

/// Everything needed to render one club's season: its fixtures and the
/// per-player profiles derived from those fixtures.
struct TeamDataset: Hashable, Codable, Sendable {
    let team: Team
    let competition: Competition
    let fixtures: [ScoutFixture]
    let players: [PlayerMetricProfile]
}

// MARK: - Team helpers

extension Team {
    init(statsBombID: Int, name: String, crestSymbol: String = "shield.fill") {
        let letters = name.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(3)
        self.init(id: "sb-\(statsBombID)", name: name, shortName: String(letters), crestSymbol: crestSymbol)
    }

    var statsBombID: Int? {
        guard id.hasPrefix("sb-") else { return nil }
        return Int(id.dropFirst(3))
    }
}

// MARK: - Array chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
