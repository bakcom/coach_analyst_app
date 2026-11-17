import SwiftUI

/// Backend-driven fixtures for the coach's own team. Tapping a fixture opens
/// the post-game report.
struct MatchesView: View {
    @Environment(ScoutingStore.self) private var store
    @State private var fixtures: [ScoutFixture] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Group {
                if let own = store.ownTeam {
                    if loading && fixtures.isEmpty {
                        ProgressView("Loading fixtures…")
                    } else if fixtures.isEmpty {
                        ContentUnavailableView("No fixtures", systemImage: "calendar")
                    } else {
                        List(fixtures) { fixture in
                            NavigationLink(value: MatchRoute(competition: own.competition, fixture: fixture)) {
                                row(fixture, own: own.team)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No team selected",
                        systemImage: "person.3.sequence.fill",
                        description: Text("In Scouting, open a club and tap “Set as my team”, then come back here.")
                    )
                }
            }
            .navigationTitle("Matches")
            .scoutingDestinations()
            .toolbar {
                if let own = store.ownTeam {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: TeamAnalysisRoute(competition: own.competition, team: own.team)) {
                            Image(systemName: "chart.xyaxis.line")
                        }
                    }
                }
            }
            .refreshable { await load() }
            .task(id: store.ownTeam?.team.id) { await load() }
        }
    }

    private func row(_ fixture: ScoutFixture, own: Team) -> some View {
        let isHome = fixture.home.id == own.id
        let us = isHome ? fixture.homeScore : fixture.awayScore
        let them = isHome ? fixture.awayScore : fixture.homeScore
        let opponent = isHome ? fixture.away : fixture.home
        let color: Color = us > them ? .green : (us < them ? .red : .secondary)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(isHome ? "vs" : "@") \(opponent.name)").font(.subheadline.weight(.medium))
                Text(fixture.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(us)–\(them)").font(.headline.monospacedDigit()).foregroundStyle(color)
        }
    }

    private func load() async {
        guard let own = store.ownTeam else { fixtures = []; return }
        loading = fixtures.isEmpty
        defer { loading = false }
        if let dataset = await store.dataset(for: own.competition, team: own.team) {
            fixtures = dataset.fixtures
        }
    }
}
