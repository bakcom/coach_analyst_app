import Foundation

/// Accumulates a player's contributions across many matches (and competitions).
struct PlayerAccumulator {
    var playerID: Int
    var name: String
    var teamName: String
    var totals = MetricTotals()
    var minutesByGroup: [PositionGroup: Double] = [:]
    var minutesByCompetition: [Int: Double] = [:]
    var nameByCompetition: [Int: String] = [:]
    var minutesByPosition: [String: Double] = [:]

    mutating func add(_ contribution: MatchPlayerContribution, competition: Competition) {
        name = contribution.name
        teamName = contribution.teamName
        totals += contribution.totals
        minutesByGroup[contribution.group, default: 0] += contribution.minutes
        minutesByCompetition[competition.competitionID, default: 0] += contribution.minutes
        nameByCompetition[competition.competitionID] = competition.name
        minutesByPosition[contribution.positionName, default: 0] += contribution.minutes
    }

    var profile: PlayerMetricProfile {
        let group = minutesByGroup.max { $0.value < $1.value }?.key ?? .midfielder
        let compID = minutesByCompetition.max { $0.value < $1.value }?.key ?? 0
        return PlayerMetricProfile(
            playerID: "sb-\(playerID)",
            name: name,
            teamName: teamName,
            competitionID: compID,
            competitionName: nameByCompetition[compID] ?? "",
            group: group,
            primaryPosition: minutesByPosition.max { $0.value < $1.value }?.key ?? "Unknown",
            totals: totals
        )
    }
}

extension PlayerAccumulator {
    static func build(
        from contributions: [[MatchPlayerContribution]],
        competition: Competition
    ) -> [PlayerMetricProfile] {
        var byPlayer: [Int: PlayerAccumulator] = [:]
        for match in contributions {
            for contribution in match {
                var accumulator = byPlayer[contribution.playerID]
                    ?? PlayerAccumulator(playerID: contribution.playerID, name: contribution.name, teamName: contribution.teamName)
                accumulator.add(contribution, competition: competition)
                byPlayer[contribution.playerID] = accumulator
            }
        }
        return byPlayer.values.map(\.profile)
    }
}

/// The concrete StatsBomb adapter used by the scouting flow.
actor StatsBombScoutingService {
    private let client: StatsBombAPIClient
    private let dateFormatter: DateFormatter

    private var competitionsCache: [Competition]?
    private var fixturesCache: [String: [ScoutFixture]] = [:]

    init(client: StatsBombAPIClient = StatsBombAPIClient()) {
        self.client = client
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        self.dateFormatter = formatter
    }

    // MARK: - Catalog

    func competitions() async throws -> [Competition] {
        if let competitionsCache { return competitionsCache }
        let dtos = try await client.competitions()
        let competitions = dtos
            .map {
                Competition(
                    competitionID: $0.competitionId,
                    seasonID: $0.seasonId,
                    name: $0.competitionName,
                    country: $0.countryName,
                    gender: $0.competitionGender,
                    seasonName: $0.seasonName
                )
            }
            .sorted { ($0.country, $0.name, $0.seasonName) < ($1.country, $1.name, $1.seasonName) }
        competitionsCache = competitions
        return competitions
    }

    func fixtures(in competition: Competition) async throws -> [ScoutFixture] {
        if let cached = fixturesCache[competition.id] { return cached }
        let matches = try await client.matches(competitionID: competition.competitionID, seasonID: competition.seasonID)
        let fixtures = matches.map { match in
            ScoutFixture(
                id: match.matchId,
                date: dateFormatter.date(from: match.matchDate) ?? .distantPast,
                home: Team(statsBombID: match.homeTeam.homeTeamId, name: match.homeTeam.homeTeamName),
                away: Team(statsBombID: match.awayTeam.awayTeamId, name: match.awayTeam.awayTeamName),
                homeScore: match.homeScore,
                awayScore: match.awayScore
            )
        }
        .sorted { $0.date > $1.date }
        fixturesCache[competition.id] = fixtures
        return fixtures
    }

    func teams(in competition: Competition) async throws -> [Team] {
        let fixtures = try await fixtures(in: competition)
        var seen: [String: Team] = [:]
        for fixture in fixtures {
            seen[fixture.home.id] = fixture.home
            seen[fixture.away.id] = fixture.away
        }
        return seen.values.sorted { $0.name < $1.name }
    }

    // MARK: - Per-match analysis

    func analyze(matchID: Int) async throws -> [MatchPlayerContribution] {
        async let lineups = client.lineups(matchID: matchID)
        async let events = client.events(matchID: matchID)
        return StatsBombAggregator.contributions(events: try await events, lineups: try await lineups)
    }
}
