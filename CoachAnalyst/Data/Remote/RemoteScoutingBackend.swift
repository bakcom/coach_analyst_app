import Foundation

/// Backend that delegates ingestion, pooled-stat storage and the similarity
/// search to the Coach Analyst BFF. The device only renders.
struct RemoteScoutingBackend: ScoutingBackend {
    let label: String
    private let api: CoachAnalystAPI

    init(baseURL: URL) {
        self.api = CoachAnalystAPI(baseURL: baseURL)
        self.label = "BFF · \(baseURL.host ?? baseURL.absoluteString)"
    }

    func competitions() async throws -> [Competition] {
        try await api.competitions()
    }

    func teams(in competition: Competition) async throws -> [Team] {
        try await api.teams(competition: competition)
    }

    func dataset(for competition: Competition, team: Team) async throws -> TeamDataset {
        try await api.dataset(competition: competition, team: team)
    }

    func poolPlayers() async throws -> [PlayerMetricProfile] {
        try await api.poolPlayers()
    }

    func buildPool(
        _ selections: [Competition],
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [PlayerMetricProfile] {
        _ = try await api.startPoolBuild(selections)

        // Poll the durable job until it finishes, with a hard deadline so a
        // missing/stalled worker surfaces an error instead of hanging forever.
        let deadline = Date().addingTimeInterval(600)
        var jobId: String?
        var lastMessage = "Queued"

        while true {
            if Date() > deadline {
                throw ScoutingError.buildFailed("Timed out after 10 min (last status: \(lastMessage)). Is the worker running?")
            }
            try await Task.sleep(nanoseconds: 800_000_000)
            let status = try await api.poolStatus(jobId: jobId)
            jobId = status.jobId
            lastMessage = status.message
            progress(status.progress)
            switch status.status {
            case "ready":
                return try await api.poolPlayers()
            case "failed":
                throw ScoutingError.buildFailed(status.message)
            default:
                continue
            }
        }
    }

    func matchAnalysis(competition: Competition, matchID: Int) async throws -> MatchAnalysis {
        try await api.matchAnalysis(competition: competition, matchID: matchID)
    }

    func teamAnalysis(competition: Competition, team: Team) async throws -> TeamAnalysis {
        try await api.teamAnalysis(competition: competition, team: team)
    }

    func similar(to profile: PlayerMetricProfile, otherCompetitionsOnly: Bool) async throws -> SimilarityEngine.Result {
        try await api.similar(profile: profile, otherCompetitionsOnly: otherCompetitionsOnly, limit: 10)
    }

    func comparison(target: PlayerMetricProfile, candidate: PlayerMetricProfile) async throws -> [MetricComparison] {
        try await api.comparison(target: target, candidate: candidate)
    }
}
