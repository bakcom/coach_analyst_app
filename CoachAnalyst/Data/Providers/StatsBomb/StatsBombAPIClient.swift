import Foundation

enum StatsBombError: LocalizedError {
    case badResponse(Int)
    case decoding(String)
    case offline

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): "StatsBomb request failed (HTTP \(code))."
        case .decoding(let detail): "Couldn't read StatsBomb data. \(detail)"
        case .offline: "Couldn't reach StatsBomb. Check your connection."
        }
    }
}

/// Thin async client over the StatsBomb **open data** repository (no API key
/// required). Swapping to the authenticated StatsBomb API only means changing
/// the base URL and adding an auth header here.
actor StatsBombAPIClient {
    static let openDataBase = URL(string: "https://raw.githubusercontent.com/statsbomb/open-data/master/data/")!

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func competitions() async throws -> [SBCompetition] {
        try await get("competitions.json")
    }

    func matches(competitionID: Int, seasonID: Int) async throws -> [SBMatch] {
        try await get("matches/\(competitionID)/\(seasonID).json")
    }

    func lineups(matchID: Int) async throws -> [SBLineupTeam] {
        try await get("lineups/\(matchID).json")
    }

    func events(matchID: Int) async throws -> [SBEvent] {
        try await get("events/\(matchID).json")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: Self.openDataBase) else {
            throw StatsBombError.badResponse(0)
        }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw StatsBombError.badResponse(http.statusCode)
            }
            return try decoder.decode(T.self, from: data)
        } catch let error as StatsBombError {
            throw error
        } catch let error as DecodingError {
            throw StatsBombError.decoding(String(describing: error))
        } catch {
            throw StatsBombError.offline
        }
    }
}
