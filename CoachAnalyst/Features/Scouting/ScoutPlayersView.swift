import SwiftUI

/// Players of a club, derived from the club's matches in the selected season.
/// Tap a player to open their profile and similar players.
struct ScoutPlayersView: View {
    let route: ScoutTeamRoute

    @Environment(ScoutingStore.self) private var store
    @State private var dataset: TeamDataset?
    @State private var isLoading = true

    var body: some View {
        List {
            if let dataset {
                if dataset.players.isEmpty {
                    Text("No players found for this club.").foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(dataset.players) { profile in
                            NavigationLink(value: profile) {
                                row(profile)
                            }
                        }
                    } header: {
                        Text("\(dataset.players.count) players · \(dataset.fixtures.count) matches analysed")
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Analysing matches…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(route.team.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        store.setOwnTeam(competition: route.competition, team: route.team)
                    } label: {
                        Label(store.isOwnTeam(route.team) ? "My team" : "Set as my team", systemImage: "star")
                    }
                    NavigationLink(value: TeamAnalysisRoute(competition: route.competition, team: route.team)) {
                        Label("Team analysis", systemImage: "chart.xyaxis.line")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            dataset = await store.dataset(for: route.competition, team: route.team)
            isLoading = false
        }
    }

    private func row(_ profile: PlayerMetricProfile) -> some View {
        HStack(spacing: 12) {
            Text(profile.group.short)
                .font(.caption2.bold())
                .frame(width: 34, height: 26)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.body.weight(.medium))
                Text(profile.primaryPosition).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(profile.minutes))′")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
