import Foundation

/// On-device backend: pulls StatsBomb open data, aggregates per-player event
/// counters, and answers similarity/comparison queries locally. The remote BFF
/// backend returns the same shapes, so the UI is identical either way.
actor LocalScoutingBackend: ScoutingBackend {
    private let service: StatsBombScoutingService
    private let maxMatchesPerCompetition: Int

    private var datasetCache: [String: TeamDataset] = [:]
    private var pool: [PlayerMetricProfile] = []

    init(
        service: StatsBombScoutingService = StatsBombScoutingService(),
        maxMatchesPerCompetition: Int = 24
    ) {
        self.service = service
        self.maxMatchesPerCompetition = maxMatchesPerCompetition
    }

    func competitions() async throws -> [Competition] {
        try await service.competitions()
    }

    func teams(in competition: Competition) async throws -> [Team] {
        try await service.teams(in: competition)
    }

    func dataset(for competition: Competition, team: Team) async throws -> TeamDataset {
        let key = "\(competition.id)-\(team.id)"
        if let cached = datasetCache[key] { return cached }

        guard let teamID = team.statsBombID else { throw ScoutingError.missingTeam }
        let fixtures = try await service.fixtures(in: competition)
        let teamFixtures = fixtures.filter { $0.home.id == team.id || $0.away.id == team.id }
        let matchIDs = Array(teamFixtures.prefix(maxMatchesPerCompetition).map(\.id))
        let contributions = await analyze(matchIDs: matchIDs, progress: nil)

        var byPlayer: [Int: PlayerAccumulator] = [:]
        for match in contributions {
            for contribution in match where contribution.teamID == teamID {
                var accumulator = byPlayer[contribution.playerID]
                    ?? PlayerAccumulator(playerID: contribution.playerID, name: contribution.name, teamName: contribution.teamName)
                accumulator.add(contribution, competition: competition)
                byPlayer[contribution.playerID] = accumulator
            }
        }

        let dataset = TeamDataset(
            team: team,
            competition: competition,
            fixtures: teamFixtures,
            players: byPlayer.values.map(\.profile).sorted { $0.minutes > $1.minutes }
        )
        datasetCache[key] = dataset
        return dataset
    }

    func poolPlayers() async throws -> [PlayerMetricProfile] {
        pool
    }

    func buildPool(
        _ selections: [Competition],
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [PlayerMetricProfile] {
        var accumulators: [Int: PlayerAccumulator] = [:]

        for (index, competition) in selections.enumerated() {
            let fixtures = try await service.fixtures(in: competition)
            let matchIDs = Array(fixtures.prefix(maxMatchesPerCompetition).map(\.id))
            let contributions = await analyze(matchIDs: matchIDs) { done, total in
                let within = total > 0 ? Double(done) / Double(total) : 1
                progress((Double(index) + within) / Double(Swift.max(selections.count, 1)))
            }
            for match in contributions {
                for contribution in match {
                    var accumulator = accumulators[contribution.playerID]
                        ?? PlayerAccumulator(playerID: contribution.playerID, name: contribution.name, teamName: contribution.teamName)
                    accumulator.add(contribution, competition: competition)
                    accumulators[contribution.playerID] = accumulator
                }
            }
        }

        pool = accumulators.values.map(\.profile).sorted { $0.name < $1.name }
        progress(1)
        return pool
    }

    func similar(to profile: PlayerMetricProfile, otherCompetitionsOnly: Bool) async throws -> SimilarityEngine.Result {
        SimilarityEngine.similar(to: profile, pool: pool, otherCompetitionsOnly: otherCompetitionsOnly)
    }

    func comparison(target: PlayerMetricProfile, candidate: PlayerMetricProfile) async throws -> [MetricComparison] {
        SimilarityEngine.comparison(target: target, candidate: candidate, population: pool)
    }

    func matchAnalysis(competition: Competition, matchID: Int) async throws -> MatchAnalysis {
        throw ScoutingError.notConfigured
    }

    func teamAnalysis(competition: Competition, team: Team) async throws -> TeamAnalysis {
        throw ScoutingError.notConfigured
    }

    // MARK: - Concurrency helper

    private func analyze(
        matchIDs: [Int],
        progress: (@Sendable (Int, Int) -> Void)?
    ) async -> [[MatchPlayerContribution]] {
        guard !matchIDs.isEmpty else { return [] }
        let service = self.service
        var output: [[MatchPlayerContribution]] = []
        var completed = 0

        for chunk in matchIDs.chunked(into: 4) {
            let results = await withTaskGroup(of: [MatchPlayerContribution]?.self) { group in
                for matchID in chunk {
                    group.addTask { try? await service.analyze(matchID: matchID) }
                }
                var collected: [[MatchPlayerContribution]] = []
                for await result in group {
                    if let result { collected.append(result) }
                }
                return collected
            }
            output.append(contentsOf: results)
            completed += chunk.count
            progress?(completed, matchIDs.count)
        }
        return output
    }
}
