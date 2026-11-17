import SwiftUI

/// Root of the StatsBomb scouting flow: pick a competition to drill into
/// (competition → clubs → players), and manage the similarity pool.
struct ScoutView: View {
    @Environment(ScoutingStore.self) private var store
    @State private var query = ""

    private var filtered: [Competition] {
        guard !query.isEmpty else { return store.competitions }
        return store.competitions.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.country.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                poolSection

                Section("Competitions") {
                    if store.isLoadingCompetitions {
                        HStack { ProgressView(); Text("Loading competitions…").foregroundStyle(.secondary) }
                    } else if let error = store.loadError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    } else {
                        ForEach(filtered) { competition in
                            competitionRow(competition)
                        }
                    }
                }
            }
            .navigationTitle("Scouting")
            .searchable(text: $query, prompt: "Search competitions")
            .scoutingDestinations()
            .task {
                await store.loadCompetitions()
                await store.loadPoolPlayers()
            }
        }
    }

    private var poolSection: some View {
        Section {
            if store.poolSelections.isEmpty {
                Text("Add competitions below to build the pool used to find similar players.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.poolSelections) { competition in
                    HStack {
                        Image(systemName: "circle.grid.2x2.fill").foregroundStyle(Color.accentColor)
                        Text(competition.displayName).font(.subheadline)
                        Spacer()
                        Button {
                            store.togglePool(competition)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if store.isBuildingPool {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: store.poolProgress)
                    Text(store.poolStatusMessage ?? "Building pool…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await store.buildPool() }
                } label: {
                    Label(store.poolProfiles.isEmpty ? "Build pool" : "Rebuild pool",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.poolSelections.isEmpty)

                if let status = store.poolStatusMessage {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                if !store.poolProfiles.isEmpty {
                    NavigationLink {
                        ScoutPoolView()
                    } label: {
                        Label("\(store.poolProfiles.count) players in pool", systemImage: "person.2.fill")
                    }
                }
            }
        } header: {
            Text("Similarity Pool")
        } footer: {
            Text("A player's similar-players list is drawn from other competitions in the pool. Backend: \(store.backendLabel).")
        }
    }

    private func competitionRow(_ competition: Competition) -> some View {
        NavigationLink(value: competition) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(competition.name).font(.body.weight(.medium))
                    Text("\(competition.country) · \(competition.seasonName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isInPool(competition) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            let inPool = store.isInPool(competition)
            Button {
                store.togglePool(competition)
            } label: {
                Label(inPool ? "Remove" : "Add to pool", systemImage: inPool ? "minus" : "plus")
            }
            .tint(inPool ? .red : .green)
        }
    }
}

/// Read-only list of everyone in the pool, grouped by competition.
struct ScoutPoolView: View {
    @Environment(ScoutingStore.self) private var store

    private var grouped: [(String, [PlayerMetricProfile])] {
        Dictionary(grouping: store.poolProfiles, by: { $0.competitionName })
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.0) { name, players in
                Section(name.isEmpty ? "Unknown" : name) {
                    ForEach(players) { profile in
                        NavigationLink(value: profile) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name).font(.body)
                                    Text("\(profile.teamName) · \(profile.group.short)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int(profile.minutes)) min")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Pool Players")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ScoutView()
        .environment(ScoutingStore())
}
