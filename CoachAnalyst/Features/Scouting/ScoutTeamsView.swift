import SwiftUI

/// Clubs that took part in the selected competition season.
struct ScoutTeamsView: View {
    let competition: Competition

    @Environment(ScoutingStore.self) private var store
    @State private var teams: [Team] = []
    @State private var isLoading = true

    var body: some View {
        List(teams) { team in
            NavigationLink(value: ScoutTeamRoute(competition: competition, team: team)) {
                Label(team.name, systemImage: team.crestSymbol)
            }
        }
        .overlay {
            if isLoading { ProgressView("Loading clubs…") }
            else if teams.isEmpty { ContentUnavailableView("No clubs", systemImage: "shield") }
        }
        .navigationTitle(competition.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            teams = await store.teams(in: competition)
            isLoading = false
        }
    }
}
