import Foundation

/// A non-2xx response or an undecodable body from the BFF.
enum APIError: LocalizedError {
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): "Backend error \(code)\(body.isEmpty ? "" : ": \(body)")"
        case .decoding(let detail): "Couldn't read the backend response. \(detail)"
        }
    }
}

/// Status of the BFF's background pool job.
struct PoolStatus: Codable, Sendable {
    let jobId: String
    let status: String // idle | queued | running | ready | failed
    let progress: Double
    let message: String
    let playerCount: Int
}

/// HTTP client for the Coach Analyst BFF (FastAPI). JSON keys match the Swift
/// domain property names exactly, so the same models decode on both sides.
actor CoachAnalystAPI {
    let baseURL: URL

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Endpoints

    func competitions() async throws -> [Competition] {
        try await get("competitions")
    }

    func teams(competition: Competition) async throws -> [Team] {
        try await get("competitions/\(competition.competitionID)/\(competition.seasonID)/teams")
    }

    func dataset(competition: Competition, team: Team) async throws -> TeamDataset {
        let teamID = team.statsBombID ?? 0
        return try await get(
            "competitions/\(competition.competitionID)/\(competition.seasonID)/teams/\(teamID)/dataset",
            query: [URLQueryItem(name: "name", value: competition.displayName)]
        )
    }

    func poolPlayers() async throws -> [PlayerMetricProfile] {
        try await get("pool")
    }

    func buildPool(_ selections: [Competition]) async throws -> [PlayerMetricProfile] {
        struct Selection: Encodable { let competitionID: Int; let seasonID: Int; let name: String }
        struct Body: Encodable { let selections: [Selection] }
        let body = Body(selections: selections.map {
            Selection(competitionID: $0.competitionID, seasonID: $0.seasonID, name: $0.displayName)
        })
        return try await post("pool/build", body: body)
    }

    func startPoolBuild(_ selections: [Competition], force: Bool = false) async throws -> PoolStatus {
        struct Selection: Encodable { let competitionID: Int; let seasonID: Int; let name: String }
        struct Body: Encodable { let selections: [Selection] }
        let body = Body(selections: selections.map {
            Selection(competitionID: $0.competitionID, seasonID: $0.seasonID, name: $0.displayName)
        })
        return try await post(
            "pool/build",
            body: body,
            query: [URLQueryItem(name: "force", value: force ? "true" : "false")]
        )
    }

    func poolStatus(jobId: String? = nil) async throws -> PoolStatus {
        if let jobId {
            return try await get("pool/status", query: [URLQueryItem(name: "jobId", value: jobId)])
        }
        return try await get("pool/status")
    }

    func matchAnalysis(competition: Competition, matchID: Int) async throws -> MatchAnalysis {
        try await get("competitions/\(competition.competitionID)/\(competition.seasonID)/matches/\(matchID)/analysis")
    }

    func teamAnalysis(competition: Competition, team: Team) async throws -> TeamAnalysis {
        try await get(
            "competitions/\(competition.competitionID)/\(competition.seasonID)/teams/\(team.statsBombID ?? 0)/analysis",
            query: [URLQueryItem(name: "name", value: competition.displayName)]
        )
    }

    func similar(profile: PlayerMetricProfile, otherCompetitionsOnly: Bool, limit: Int) async throws -> SimilarityEngine.Result {
        struct Body: Encodable {
            let profile: PlayerMetricProfile
            let otherCompetitionsOnly: Bool
            let limit: Int
        }
        return try await post("players/similar", body: Body(profile: profile, otherCompetitionsOnly: otherCompetitionsOnly, limit: limit))
    }

    func comparison(target: PlayerMetricProfile, candidate: PlayerMetricProfile) async throws -> [MetricComparison] {
        struct Body: Encodable {
            let target: PlayerMetricProfile
            let candidate: PlayerMetricProfile
        }
        return try await post("comparison", body: Body(target: target, candidate: candidate))
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let request = try makeRequest(method: "GET", path: path, query: query, body: nil)
        return try await send(request)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body, query: [URLQueryItem] = []) async throws -> T {
        let request = try makeRequest(method: "POST", path: path, query: query, body: try encoder.encode(body))
        return try await send(request)
    }

    private func makeRequest(method: String, path: String, query: [URLQueryItem], body: Data?) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data.prefix(300), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw APIError.http(http.statusCode, body)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw APIError.decoding(String(describing: error))
        }
    }
}
