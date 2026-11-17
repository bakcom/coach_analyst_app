import SwiftUI

/// Season report for a club — used both for the coach's own team and for
/// opponent analysis. Style radar, key metrics, recent form and top players.
struct TeamAnalysisView: View {
    let competition: Competition
    let team: Team

    @Environment(ScoutingStore.self) private var store
    @State private var analysis: TeamAnalysis?
    @State private var errorMessage: String?
    @State private var loading = true

    var body: some View {
        List {
            if let analysis {
                headerSection(analysis)
                styleSection(analysis)
                metricsSection(analysis)
                recentSection(analysis)
                playersSection(analysis)
            } else if loading {
                HStack { ProgressView(); Text("Building report…").foregroundStyle(.secondary) }
            } else {
                Text(errorMessage ?? "No analysis available.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Sections

    private func headerSection(_ analysis: TeamAnalysis) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(store.isOwnTeam(team) ? "MY TEAM" : "OPPONENT")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background((store.isOwnTeam(team) ? Color.accentColor : Color.orange).opacity(0.15), in: Capsule())
                    Spacer()
                    Text("\(analysis.stats.matches) matches analysed")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(analysis.team.name).font(.title3.bold())
                Text(analysis.competition.displayName).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func styleSection(_ analysis: TeamAnalysis) -> some View {
        Section("Style profile") {
            RadarChart(axes: Self.styleAxes, series: [styleSeries(analysis)])
                .frame(height: 280)
                .padding(.vertical, 6)
        }
    }

    private static let styleAxes = ["Poss", "Pass%", "Passes", "ProgP", "3rdP", "Shots", "xG", "HighT"]

    private func styleSeries(_ analysis: TeamAnalysis) -> RadarChart.Series {
        let s = analysis.stats
        let values = [
            clamp(s.possession / 100),
            clamp(s.passAccuracy),
            clamp(s.passes / 550),
            clamp(s.progressivePasses / 45),
            clamp(s.finalThirdPasses / 40),
            clamp(s.shots / 18),
            clamp(s.xg / 2.5),
            clamp(s.highTurnovers / 14)
        ]
        return .init(name: analysis.team.shortName, color: .accentColor, values: values)
    }

    private func clamp(_ value: Double) -> Double { max(0, min(1, value)) }

    private func metricsSection(_ analysis: TeamAnalysis) -> some View {
        Section("Key metrics · per match") {
            metric("Possession", String(format: "%.0f%%", analysis.stats.possession))
            metric("xG for", String(format: "%.2f", analysis.stats.xg))
            metric("Goals for", String(format: "%.1f", analysis.stats.goals))
            metric("Shots", String(format: "%.1f (%.1f on target)", analysis.stats.shots, analysis.stats.shotsOnTarget))
            metric("Pass accuracy", String(format: "%.0f%%", analysis.stats.passAccuracy * 100))
            metric("Progressive passes", String(format: "%.1f", analysis.stats.progressivePasses))
            metric("Final-third passes", String(format: "%.1f", analysis.stats.finalThirdPasses))
            metric("Box entries", String(format: "%.1f", analysis.stats.boxEntries))
            metric("PPDA", String(format: "%.2f", analysis.stats.ppda))
            metric("High turnovers", String(format: "%.1f", analysis.stats.highTurnovers))
        }
    }

    private func recentSection(_ analysis: TeamAnalysis) -> some View {
        Section("Recent form") {
            if analysis.stats.recent.isEmpty {
                Text("No recent matches.").foregroundStyle(.secondary)
            } else {
                ForEach(analysis.stats.recent.reversed()) { match in
                    HStack(spacing: 10) {
                        Text(match.result)
                            .font(.caption.bold())
                            .frame(width: 22, height: 22)
                            .background(resultColor(match.result).opacity(0.18), in: Circle())
                            .foregroundStyle(resultColor(match.result))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(match.home ? "vs" : "@") \(match.opponent)").font(.subheadline)
                            Text(match.date).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(match.goalsFor)–\(match.goalsAgainst)").font(.subheadline.monospacedDigit())
                            Text(String(format: "%.2f xG", match.xg)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func playersSection(_ analysis: TeamAnalysis) -> some View {
        Section("Top players") {
            if analysis.players.isEmpty {
                Text("No players.").foregroundStyle(.secondary)
            } else {
                ForEach(analysis.players) { player in
                    HStack(spacing: 10) {
                        Text(player.group.short)
                            .font(.caption2.bold())
                            .frame(width: 34, height: 24)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(player.name).font(.subheadline.weight(.medium))
                            Text(player.primaryPosition).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(player.minutes))′").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func resultColor(_ result: String) -> Color {
        switch result {
        case "W": .green
        case "L": .red
        default: .secondary
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            analysis = try await store.teamAnalysis(competition: competition, team: team)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
