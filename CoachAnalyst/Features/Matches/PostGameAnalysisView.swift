import SwiftUI

/// Post-game report for a single match: score, head-to-head team stats,
/// momentum, shot map and top performers.
struct PostGameAnalysisView: View {
    let route: MatchRoute

    @Environment(ScoutingStore.self) private var store
    @State private var analysis: MatchAnalysis?
    @State private var errorMessage: String?
    @State private var loading = true

    private let homeColor = Color.accentColor
    private let awayColor = Color.orange

    var body: some View {
        List {
            if let analysis {
                headerSection(analysis)
                statsSection(analysis)
                momentumSection(analysis)
                shotMapSection(analysis)
                performersSection(analysis)
            } else if loading {
                HStack { ProgressView(); Text("Analysing match…").foregroundStyle(.secondary) }
            } else {
                Text(errorMessage ?? "No analysis available.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var title: String {
        "\(route.fixture.home.shortName) \(route.fixture.homeScore)–\(route.fixture.awayScore) \(route.fixture.away.shortName)"
    }

    // MARK: - Sections

    private func headerSection(_ analysis: MatchAnalysis) -> some View {
        Section {
            HStack {
                teamColumn(analysis.home.team, color: homeColor)
                Spacer()
                VStack(spacing: 2) {
                    Text("\(analysis.match.homeScore) – \(analysis.match.awayScore)")
                        .font(.title.bold().monospacedDigit())
                    Text(analysis.match.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                teamColumn(analysis.away.team, color: awayColor)
            }
            .padding(.vertical, 4)
        }
    }

    private func teamColumn(_ team: Team, color: Color) -> some View {
        VStack(spacing: 4) {
            Circle().fill(color.opacity(0.15)).frame(width: 40, height: 40)
                .overlay(Image(systemName: team.crestSymbol).foregroundStyle(color))
            Text(team.shortName).font(.caption.bold())
        }
        .frame(width: 72)
    }

    private func statsSection(_ analysis: MatchAnalysis) -> some View {
        Section("Team stats") {
            let rows: [(String, Double, Double, (Double) -> String)] = [
                ("Possession", analysis.home.stats.possession, analysis.away.stats.possession, { String(format: "%.0f%%", $0) }),
                ("xG", analysis.home.stats.xg, analysis.away.stats.xg, { String(format: "%.2f", $0) }),
                ("Shots", analysis.home.stats.shots, analysis.away.stats.shots, { String(format: "%.0f", $0) }),
                ("On target", analysis.home.stats.shotsOnTarget, analysis.away.stats.shotsOnTarget, { String(format: "%.0f", $0) }),
                ("Pass accuracy", analysis.home.stats.passAccuracy, analysis.away.stats.passAccuracy, { String(format: "%.0f%%", $0 * 100) }),
                ("Prog. passes", analysis.home.stats.progressivePasses, analysis.away.stats.progressivePasses, { String(format: "%.0f", $0) }),
                ("Final-third passes", analysis.home.stats.finalThirdPasses, analysis.away.stats.finalThirdPasses, { String(format: "%.0f", $0) }),
                ("Box entries", analysis.home.stats.boxEntries, analysis.away.stats.boxEntries, { String(format: "%.0f", $0) }),
                ("PPDA", analysis.home.stats.ppda, analysis.away.stats.ppda, { String(format: "%.2f", $0) })
            ]
            ForEach(rows, id: \.0) { label, home, away, format in
                ComparisonRow(
                    label: label,
                    home: format(home),
                    away: format(away),
                    homeFraction: share(home, away),
                    homeColor: homeColor,
                    awayColor: awayColor
                )
            }
        }
    }

    private func momentumSection(_ analysis: MatchAnalysis) -> some View {
        Section("Momentum · xG per 5 min") {
            MomentumChart(buckets: analysis.momentum, homeColor: homeColor, awayColor: awayColor)
                .frame(height: 120)
                .padding(.vertical, 6)
        }
    }

    private func shotMapSection(_ analysis: MatchAnalysis) -> some View {
        Section("Shot map · size = xG") {
            ShotMap(
                shots: analysis.shots,
                homeTeamID: Int(analysis.home.team.id.split(separator: "-").last ?? "0") ?? 0,
                homeColor: homeColor,
                awayColor: awayColor
            )
            .frame(height: 200)
            .padding(.vertical, 4)
        }
    }

    private func performersSection(_ analysis: MatchAnalysis) -> some View {
        Group {
            performerList("Top · \(analysis.home.team.shortName)", players: analysis.home.players, color: homeColor)
            performerList("Top · \(analysis.away.team.shortName)", players: analysis.away.players, color: awayColor)
        }
    }

    private func performerList(_ title: String, players: [PlayerImpact], color: Color) -> some View {
        Section(title) {
            ForEach(players.prefix(5)) { player in
                HStack(spacing: 10) {
                    Text(String(format: "%.1f", player.impact))
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 34, height: 26)
                        .background(color.opacity(0.15), in: Capsule())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.name).font(.subheadline.weight(.medium))
                        Text("\(player.minutes)′ · \(player.goals)G \(player.assists)A · \(String(format: "%.2f", player.xg)) xG")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private func share(_ home: Double, _ away: Double) -> Double {
        let total = home + away
        return total > 0 ? home / total : 0.5
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            analysis = try await store.matchAnalysis(competition: route.competition, matchID: route.fixture.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Components

private struct ComparisonRow: View {
    let label: String
    let home: String
    let away: String
    let homeFraction: Double
    let homeColor: Color
    let awayColor: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(home).font(.subheadline.monospacedDigit().weight(.medium))
                Spacer()
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(away).font(.subheadline.monospacedDigit().weight(.medium))
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Capsule().fill(homeColor.opacity(0.8))
                        .frame(width: max(2, geo.size.width * homeFraction - 1))
                    Capsule().fill(awayColor.opacity(0.8))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }
}

private struct MomentumChart: View {
    let buckets: [MomentumBucket]
    let homeColor: Color
    let awayColor: Color

    var body: some View {
        GeometryReader { geo in
            let peak = max(buckets.map { max($0.home, $0.away) }.max() ?? 0.1, 0.1)
            let mid = geo.size.height / 2
            let width = geo.size.width / CGFloat(max(buckets.count, 1))

            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                    .position(x: geo.size.width / 2, y: mid)

                ForEach(buckets.indices, id: \.self) { index in
                    let bucket = buckets[index]
                    let x = width * CGFloat(index) + width / 2
                    let homeHeight = CGFloat(bucket.home / peak) * (mid - 6)
                    let awayHeight = CGFloat(bucket.away / peak) * (mid - 6)

                    Rectangle().fill(homeColor)
                        .frame(width: width * 0.62, height: max(1, homeHeight))
                        .position(x: x, y: mid - homeHeight / 2)
                    Rectangle().fill(awayColor)
                        .frame(width: width * 0.62, height: max(1, awayHeight))
                        .position(x: x, y: mid + awayHeight / 2)
                }
            }
        }
    }
}

private struct ShotMap: View {
    let shots: [ShotItem]
    let homeTeamID: Int
    let homeColor: Color
    let awayColor: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.08))
                RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.35))
                Rectangle().fill(Color.green.opacity(0.25)).frame(width: 1).position(x: width / 2, y: height / 2)
                Circle().stroke(Color.green.opacity(0.25)).frame(width: height * 0.28).position(x: width / 2, y: height / 2)

                ForEach(shots) { shot in
                    Circle()
                        .fill(color(shot).opacity(shot.isGoal ? 0.9 : 0.3))
                        .overlay(Circle().stroke(color(shot), lineWidth: shot.isGoal ? 2 : 1))
                        .frame(width: max(7, CGFloat(shot.xg) * 70), height: max(7, CGFloat(shot.xg) * 70))
                        .position(x: width * CGFloat(shot.x) / 120, y: height * (1 - CGFloat(shot.y) / 80))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func color(_ shot: ShotItem) -> Color {
        shot.teamID == homeTeamID ? homeColor : awayColor
    }
}
