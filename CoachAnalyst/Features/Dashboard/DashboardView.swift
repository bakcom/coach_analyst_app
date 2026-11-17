import SwiftUI

/// Home screen. Summarises the coach's own team — recent results and top
/// performers — sourced from the same backend as the scouting flow.
struct DashboardView: View {
    @Environment(ScoutingStore.self) private var store
    @Environment(AuthStore.self) private var auth

    @State private var dataset: TeamDataset?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greeting

                    if store.ownTeam == nil {
                        noTeam
                    } else if loading && dataset == nil {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        recentForm
                        topPerformers
                    }

                    dataSourceSection
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .scoutingDestinations()
            .refreshable { await load() }
            .task(id: store.ownTeam?.team.id) { await load() }
        }
    }

    // MARK: - Sections

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back,").font(.subheadline).foregroundStyle(.secondary)
            Text(auth.currentUser?.name ?? "Coach").font(.title.bold())
            Text(store.ownTeam.map { "\($0.team.name) · \(store.ownTeam?.competition.displayName ?? "")" } ?? "No team selected")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var noTeam: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pick your team to personalise the dashboard", systemImage: "star")
                .font(.subheadline.weight(.semibold))
            Text("Open Scouting, choose a club, then tap ⋯ → “Set as my team”.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var recentForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recent matches")
            ForEach(Array((dataset?.fixtures ?? []).prefix(5))) { fixture in
                if let own = store.ownTeam?.team {
                    HStack {
                        resultBadge(Outcome(fixture: fixture, own: own))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(opponentText(fixture, own: own)).font(.subheadline.weight(.semibold))
                            Text(fixture.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(scoreText(fixture, own: own)).font(.headline.monospacedDigit())
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var topPerformers: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Squad")
            ForEach(Array((dataset?.players ?? []).prefix(5))) { player in
                NavigationLink(value: player) {
                    HStack(spacing: 12) {
                        Text(player.group.short)
                            .font(.caption2.bold())
                            .frame(width: 34, height: 26)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name).font(.subheadline.weight(.semibold))
                            Text("\(player.primaryPosition) · \(Int(player.minutes))′")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var dataSourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Data")
            HStack(spacing: 12) {
                Image(systemName: DataSource.statsBomb.symbol).foregroundStyle(Color.accentColor).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DataSource.statsBomb.displayName).font(.subheadline.weight(.semibold))
                    Text(DataSource.statsBomb.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            Text("Backend: \(store.backendLabel)")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private struct Outcome {
        let won: Bool
        let drew: Bool
        init(fixture: ScoutFixture, own: Team) {
            let isHome = fixture.home.id == own.id
            let us = isHome ? fixture.homeScore : fixture.awayScore
            let them = isHome ? fixture.awayScore : fixture.homeScore
            won = us > them
            drew = us == them
        }
    }

    private func resultBadge(_ outcome: Outcome) -> some View {
        let letter = outcome.drew ? "D" : (outcome.won ? "W" : "L")
        let color: Color = outcome.drew ? .secondary : (outcome.won ? .green : .red)
        return Text(letter)
            .font(.caption.bold())
            .frame(width: 24, height: 24)
            .background(color.opacity(0.18), in: Circle())
            .foregroundStyle(color)
    }

    private func opponentText(_ fixture: ScoutFixture, own: Team) -> String {
        let isHome = fixture.home.id == own.id
        let opponent = isHome ? fixture.away : fixture.home
        return "\(isHome ? "vs" : "@") \(opponent.name)"
    }

    private func scoreText(_ fixture: ScoutFixture, own: Team) -> String {
        let isHome = fixture.home.id == own.id
        let us = isHome ? fixture.homeScore : fixture.awayScore
        let them = isHome ? fixture.awayScore : fixture.homeScore
        return "\(us)–\(them)"
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.headline)
    }

    private func load() async {
        guard let own = store.ownTeam else { dataset = nil; return }
        if dataset == nil { loading = true }
        defer { loading = false }
        dataset = await store.dataset(for: own.competition, team: own.team)
    }
}

#Preview {
    DashboardView()
        .environment(AuthStore())
        .environment(ScoutingStore())
}
