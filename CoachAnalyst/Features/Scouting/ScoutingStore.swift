import Foundation
import Observation

/// Drives the StatsBomb scouting flow. Owns the competition catalog and the
/// user-managed similarity pool, delegating all data work to a `ScoutingBackend`
/// (local on-device, or the remote BFF).
@MainActor
@Observable
final class ScoutingStore {
    // Catalog
    var competitions: [Competition] = []
    var isLoadingCompetitions = false
    var loadError: String?

    // Similarity pool (competitions the user has added)
    var poolSelections: [Competition] = []
    var poolProfiles: [PlayerMetricProfile] = []
    var poolProgress: Double = 0
    var poolStatusMessage: String?
    var isBuildingPool = false

    /// The coach's own team, used by the Matches tab and team reports.
    var ownTeam: OwnTeam?

    private static let ownTeamKey = "ownTeam"

    /// How the app reaches scouting data. Defaults to local; set to a remote
    /// backend URL to offload ingestion + similarity to the BFF.
    let backendLabel: String
    private let backend: any ScoutingBackend

    init(backend: any ScoutingBackend) {
        self.backend = backend
        self.backendLabel = (backend as? RemoteScoutingBackend)?.label ?? "On-device"
        if let data = UserDefaults.standard.data(forKey: Self.ownTeamKey) {
            ownTeam = try? JSONDecoder().decode(OwnTeam.self, from: data)
        }
    }

    convenience init() {
        self.init(backend: BackendConfig.makeBackend())
    }

    // MARK: - Catalog

    func loadCompetitions() async {
        guard competitions.isEmpty else { return }
        isLoadingCompetitions = true
        defer { isLoadingCompetitions = false }
        do {
            competitions = try await backend.competitions()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func teams(in competition: Competition) async -> [Team] {
        (try? await backend.teams(in: competition)) ?? []
    }

    func dataset(for competition: Competition, team: Team) async -> TeamDataset? {
        try? await backend.dataset(for: competition, team: team)
    }

    // MARK: - Pool

    func isInPool(_ competition: Competition) -> Bool {
        poolSelections.contains(where: { $0.id == competition.id })
    }

    func togglePool(_ competition: Competition) {
        if let index = poolSelections.firstIndex(where: { $0.id == competition.id }) {
            poolSelections.remove(at: index)
        } else {
            poolSelections.append(competition)
        }
    }

    func buildPool() async {
        guard !isBuildingPool else { return }
        guard !poolSelections.isEmpty else {
            poolStatusMessage = "Add at least one competition to the pool."
            return
        }
        isBuildingPool = true
        poolProgress = 0
        poolStatusMessage = "Building pool…"
        defer { isBuildingPool = false }

        do {
            let profiles = try await backend.buildPool(poolSelections) { value in
                Task { @MainActor in self.poolProgress = value }
            }
            poolProfiles = profiles
            poolStatusMessage = "Pool ready · \(profiles.count) players from \(poolSelections.count) competition(s)."
        } catch {
            poolStatusMessage = "Pool build failed: \(error.localizedDescription)"
        }
    }

    func loadPoolPlayers() async {
        if let profiles = try? await backend.poolPlayers() { poolProfiles = profiles }
    }

    // MARK: - Similarity

    func similar(to profile: PlayerMetricProfile, otherCompetitionsOnly: Bool) async -> SimilarityEngine.Result {
        (try? await backend.similar(to: profile, otherCompetitionsOnly: otherCompetitionsOnly))
            ?? SimilarityEngine.Result(similar: [], populationSize: 0)
    }

    func comparison(target: PlayerMetricProfile, candidate: PlayerMetricProfile) async -> [MetricComparison] {
        (try? await backend.comparison(target: target, candidate: candidate)) ?? []
    }

    // MARK: - Own team

    func setOwnTeam(competition: Competition, team: Team) {
        let value = OwnTeam(competition: competition, team: team)
        ownTeam = value
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: Self.ownTeamKey)
        }
    }

    func clearOwnTeam() {
        ownTeam = nil
        UserDefaults.standard.removeObject(forKey: Self.ownTeamKey)
    }

    func isOwnTeam(_ team: Team) -> Bool { ownTeam?.team.id == team.id }

    // MARK: - Analytics (server-side)

    func matchAnalysis(competition: Competition, matchID: Int) async throws -> MatchAnalysis {
        try await backend.matchAnalysis(competition: competition, matchID: matchID)
    }

    func teamAnalysis(competition: Competition, team: Team) async throws -> TeamAnalysis {
        try await backend.teamAnalysis(competition: competition, team: team)
    }
}
