import Foundation

enum ScoutingError: LocalizedError {
    case missingTeam
    case notConfigured
    case buildFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingTeam: "This club has no StatsBomb identifier."
        case .notConfigured: "This needs the BFF backend — set its URL in Profile → Data Backend."
        case .buildFailed(let reason): "Pool build failed: \(reason)"
        }
    }
}

/// The data contract the scouting UI depends on. Two implementations exist:
/// `LocalScoutingBackend` (computes on-device from StatsBomb open data) and
/// `RemoteScoutingBackend` (talks to the FastAPI BFF, which owns ingestion,
/// pooled-stat storage and the similarity search).
protocol ScoutingBackend: Sendable {
    func competitions() async throws -> [Competition]
    func teams(in competition: Competition) async throws -> [Team]
    func dataset(for competition: Competition, team: Team) async throws -> TeamDataset

    /// The current pooled players (for the similarity search).
    func poolPlayers() async throws -> [PlayerMetricProfile]

    /// Rebuilds the pool from the given competition seasons, reporting progress
    /// in 0...1.
    func buildPool(
        _ selections: [Competition],
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [PlayerMetricProfile]

    func similar(
        to profile: PlayerMetricProfile,
        otherCompetitionsOnly: Bool
    ) async throws -> SimilarityEngine.Result

    func comparison(
        target: PlayerMetricProfile,
        candidate: PlayerMetricProfile
    ) async throws -> [MetricComparison]

    // Analytics (server-side; the on-device backend does not implement these).
    func matchAnalysis(competition: Competition, matchID: Int) async throws -> MatchAnalysis
    func teamAnalysis(competition: Competition, team: Team) async throws -> TeamAnalysis
}
