import SwiftUI

/// The coach's own squad, derived from the team's matches on the backend.
struct SquadView: View {
    @Environment(ScoutingStore.self) private var store

    @State private var dataset: TeamDataset?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Group {
                if store.ownTeam == nil {
                    ContentUnavailableView(
                        "No team selected",
                        systemImage: "person.3.sequence.fill",
                        description: Text("Pick your team in the Scouting tab (⋯ → “Set as my team”).")
                    )
                } else if let dataset, !dataset.players.isEmpty {
                    List(dataset.players) { player in
                        NavigationLink(value: player) { row(player) }
                    }
                } else if loading {
                    ProgressView("Loading squad…")
                } else {
                    ContentUnavailableView("No squad found", systemImage: "person.3")
                }
            }
            .navigationTitle(store.ownTeam?.team.name ?? "Squad")
            .scoutingDestinations()
            .refreshable { await load() }
            .task(id: store.ownTeam?.team.id) { await load() }
        }
    }

    private func row(_ player: PlayerMetricProfile) -> some View {
        HStack(spacing: 12) {
            Text(player.group.short)
                .font(.caption2.bold())
                .frame(width: 34, height: 26)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name).font(.body.weight(.medium))
                Text("\(player.primaryPosition) · \(Int(player.minutes))′")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func load() async {
        guard let own = store.ownTeam else { dataset = nil; return }
        if dataset == nil { loading = true }
        defer { loading = false }
        dataset = await store.dataset(for: own.competition, team: own.team)
    }
}

#Preview {
    SquadView()
        .environment(ScoutingStore())
}
