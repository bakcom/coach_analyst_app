import Foundation

/// A single player's contribution to one match: minutes + primary position from
/// the lineup, raw event counters from the event stream.
struct MatchPlayerContribution: Sendable {
    let playerID: Int
    var name: String
    var teamID: Int
    var teamName: String
    var minutes: Double
    var positionName: String
    var group: PositionGroup
    var totals: MetricTotals
}

/// Turns raw StatsBomb lineups + events for one match into per-player counters.
enum StatsBombAggregator {

    static func contributions(events: [SBEvent], lineups: [SBLineupTeam]) -> [MatchPlayerContribution] {
        let matchLength = Double(events.map(\.minute).max() ?? 90)
        var byPlayer: [Int: MatchPlayerContribution] = [:]

        // 1. Minutes + primary position from the lineups.
        for team in lineups {
            for player in team.lineup {
                let (minutes, bestPosition) = positionMinutes(player.positions, matchLength: matchLength)
                byPlayer[player.playerId] = MatchPlayerContribution(
                    playerID: player.playerId,
                    name: player.playerNickname ?? player.playerName,
                    teamID: team.teamId,
                    teamName: team.teamName,
                    minutes: minutes,
                    positionName: bestPosition,
                    group: PositionGroup.from(positionName: bestPosition),
                    totals: MetricTotals(minutes: minutes)
                )
            }
        }

        // 2. Assists: a pass is an assist if it is the key pass of a goal.
        var assistPassIDs = Set<String>()
        for event in events {
            guard event.type.name == "Shot",
                  event.shot?.outcome?.name == "Goal",
                  let keyPassID = event.shot?.keyPassId else { continue }
            assistPassIDs.insert(keyPassID)
        }

        // 3. Accumulate counters.
        for event in events {
            guard let player = event.player else { continue }
            let id = player.id

            var contribution = byPlayer[id] ?? MatchPlayerContribution(
                playerID: id,
                name: player.name,
                teamID: event.team.id,
                teamName: event.team.name,
                minutes: 0,
                positionName: "Unknown",
                group: .midfielder,
                totals: MetricTotals()
            )

            accumulate(event: event, assistPassIDs: assistPassIDs, into: &contribution.totals)
            byPlayer[id] = contribution
        }

        return Array(byPlayer.values)
    }

    // MARK: - Event counters

    private static func accumulate(event: SBEvent, assistPassIDs: Set<String>, into totals: inout MetricTotals) {
        let start = event.location
        let inBox = start.map(isInBox) ?? false

        switch event.type.name {
        case "Pass":
            guard let pass = event.pass else { break }
            totals.passesAttempted += 1
            if pass.outcome == nil { totals.passesCompleted += 1 }
            if let end = pass.endLocation, let start {
                if end[0] - start[0] >= 10 { totals.progressivePasses += 1 }
                if end[0] >= 80 { totals.finalThirdPasses += 1 }
            }
            if pass.assistedShotId != nil { totals.keyPasses += 1 }
            if pass.goalAssist == true || assistPassIDs.contains(event.id) { totals.assists += 1 }
            if inBox { totals.touchesInBox += 1 }

        case "Shot":
            guard let shot = event.shot else { break }
            totals.shots += 1
            totals.xg += shot.statsbombXg ?? 0
            if shot.outcome?.name == "Goal" { totals.goals += 1 }
            if inBox { totals.touchesInBox += 1 }

        case "Carry":
            guard let carry = event.carry else { break }
            totals.carries += 1
            if let end = carry.endLocation, let start, end[0] - start[0] >= 10 {
                totals.progressiveCarries += 1
            }
            if inBox { totals.touchesInBox += 1 }

        case "Dribble":
            if event.dribble?.outcome?.name == "Complete" { totals.dribblesCompleted += 1 }

        case "Duel":
            if let duel = event.duel {
                let type = duel.type?.name ?? ""
                let outcome = duel.outcome?.name ?? ""
                if type == "Tackle", outcome == "Won" || outcome == "Success In Play" {
                    totals.tacklesWon += 1
                }
            }

        case "Interception":
            totals.interceptions += 1

        case "Clearance":
            totals.clearances += 1

        case "Ball Recovery":
            totals.ballRecoveries += 1

        case "Pressure":
            totals.pressures += 1

        case "Goal Keeper":
            if event.goalkeeper?.type?.name.contains("Saved") == true { totals.saves += 1 }

        default:
            break
        }
    }

    // MARK: - Helpers

    /// StatsBomb pitch is 120x80. Penalty area: x >= 102, y in 18...62.
    private static func isInBox(_ location: [Double]) -> Bool {
        guard location.count >= 2 else { return false }
        return location[0] >= 102 && location[1] >= 18 && location[1] <= 62
    }

    private static func positionMinutes(_ positions: [SBPosition], matchLength: Double) -> (Double, String) {
        var total = 0.0
        var byPosition: [String: Double] = [:]

        for position in positions {
            let start = parseClock(position.from)
            let end = position.to.map(parseClock) ?? matchLength
            let duration = max(0, end - start)
            total += duration
            byPosition[position.position, default: 0] += duration
        }

        let primary = byPosition.max { $0.value < $1.value }?.key ?? "Unknown"
        return (total, primary)
    }

    /// "72:31" -> 72.52 minutes.
    private static func parseClock(_ clock: String) -> Double {
        let parts = clock.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return 0 }
        return minutes + seconds / 60
    }
}
