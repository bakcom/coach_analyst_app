import Foundation

// MARK: - Decodable DTOs for the StatsBomb open-data JSON.
//
// Decoded with `.convertFromSnakeCase`, so Swift property names are camelCase
// versions of the JSON keys (e.g. `statsbomb_xg` -> `statsbombXg`).

struct SBCompetition: Decodable, Sendable {
    let competitionId: Int
    let seasonId: Int
    let countryName: String
    let competitionName: String
    let competitionGender: String
    let seasonName: String
}

struct SBMatch: Decodable, Sendable {
    let matchId: Int
    let matchDate: String
    let homeTeam: SBHomeTeam
    let awayTeam: SBAwayTeam
    let homeScore: Int
    let awayScore: Int
}

struct SBHomeTeam: Decodable, Sendable {
    let homeTeamId: Int
    let homeTeamName: String
}

struct SBAwayTeam: Decodable, Sendable {
    let awayTeamId: Int
    let awayTeamName: String
}

struct SBLineupTeam: Decodable, Sendable {
    let teamId: Int
    let teamName: String
    let lineup: [SBLineupPlayer]
}

struct SBLineupPlayer: Decodable, Sendable {
    let playerId: Int
    let playerName: String
    let playerNickname: String?
    let jerseyNumber: Int?
    let country: SBCountry?
    let positions: [SBPosition]
}

struct SBCountry: Decodable, Sendable {
    let id: Int
    let name: String
}

struct SBPosition: Decodable, Sendable {
    let positionId: Int
    let position: String
    let from: String
    let to: String?
    let startReason: String?
    let endReason: String?
}

struct SBNamed: Decodable, Sendable {
    let id: Int?
    let name: String
}

struct SBTeamRef: Decodable, Sendable {
    let id: Int
    let name: String
}

struct SBPlayerRef: Decodable, Sendable {
    let id: Int
    let name: String
}

struct SBEvent: Decodable, Sendable {
    let id: String
    let minute: Int
    let type: SBNamed
    let team: SBTeamRef
    let player: SBPlayerRef?
    let location: [Double]?
    let pass: SBPass?
    let shot: SBShot?
    let dribble: SBOutcome?
    let duel: SBDuel?
    let interception: SBOutcome?
    let clearance: SBClearance?
    let goalkeeper: SBGoalkeeper?
    let carry: SBCarry?
    let ballRecovery: SBBallRecovery?
}

struct SBPass: Decodable, Sendable {
    let recipient: SBPlayerRef?
    let length: Double?
    let angle: Double?
    let height: SBNamed?
    let endLocation: [Double]?
    let bodyPart: SBNamed?
    let type: SBNamed?
    let outcome: SBNamed?
    let goalAssist: Bool?
    let assistedShotId: String?
}

struct SBShot: Decodable, Sendable {
    let statsbombXg: Double?
    let outcome: SBNamed?
    let keyPassId: String?
    let endLocation: [Double]?
    let bodyPart: SBNamed?
    let technique: SBNamed?
}

struct SBOutcome: Decodable, Sendable {
    let outcome: SBNamed?
}

struct SBDuel: Decodable, Sendable {
    let type: SBNamed?
    let outcome: SBNamed?
}

struct SBClearance: Decodable, Sendable {
    let bodyPart: SBNamed?
}

struct SBGoalkeeper: Decodable, Sendable {
    let type: SBNamed?
    let outcome: SBNamed?
    let endLocation: [Double]?
    let position: SBNamed?
}

struct SBCarry: Decodable, Sendable {
    let endLocation: [Double]?
}

struct SBBallRecovery: Decodable, Sendable {
    let offensive: Bool?
}
