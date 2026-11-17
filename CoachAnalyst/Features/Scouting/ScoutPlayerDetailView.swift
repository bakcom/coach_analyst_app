import SwiftUI

/// A player's position-aware metric profile plus the most similar players from
/// other competitions in the pool.
///
/// Tapping a similar player pushes the full comparison; swiping a row slides the
/// comparison in over the profile without navigating away.
struct ScoutPlayerDetailView: View {
    let profile: PlayerMetricProfile

    @Environment(ScoutingStore.self) private var store
    @State private var otherCompetitionsOnly = true
    @State private var result = SimilarityEngine.Result(similar: [], populationSize: 0)
    @State private var loading = true
    @State private var inlineCandidate: PlayerMetricProfile?

    private var metrics: [ScoutMetric] { ScoutMetric.metrics(for: profile.group) }

    var body: some View {
        List {
            headerSection
            metricsSection
            similarSection
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: otherCompetitionsOnly) {
            loading = true
            result = await store.similar(to: profile, otherCompetitionsOnly: otherCompetitionsOnly)
            loading = false
        }
        .overlay {
            if let candidate = inlineCandidate {
                ComparisonPanel(target: profile, candidate: candidate) {
                    inlineCandidate = nil
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: inlineCandidate)
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(profile.group.rawValue)
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    Spacer()
                    Text("\(Int(profile.minutes))′ played")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(profile.name).font(.title3.bold())
                Text("\(profile.teamName) · \(profile.competitionName)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(profile.primaryPosition).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var metricsSection: some View {
        Section("Key metrics · \(profile.group.short)") {
            ForEach(metrics, id: \.self) { metric in
                HStack {
                    Text(metric.title)
                    Spacer()
                    Text(profile.display(metric))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(metric.unit)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 26, alignment: .leading)
                }
            }
        }
    }

    private var similarSection: some View {
        Section {
            Toggle("Other competitions only", isOn: $otherCompetitionsOnly)

            if store.poolProfiles.isEmpty {
                Text("The similarity pool is empty. Go back, add competitions to the pool and build it.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if loading {
                HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
            } else if result.similar.isEmpty {
                Text("No comparable players found in the pool for this role yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(result.similar) { similar in
                    NavigationLink(value: ScoutComparisonRoute(target: profile, candidate: similar.profile)) {
                        similarRow(similar)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            inlineCandidate = similar.profile
                        } label: {
                            Label("Compare", systemImage: "arrow.left.arrow.right")
                        }
                        .tint(.accentColor)
                    }
                }
            }
        } header: {
            Text("Similar players")
        } footer: {
            if result.populationSize > 0 {
                Text("Compared against \(result.populationSize) \(profile.group.rawValue.lowercased())s in the pool. Tap for full screen, swipe for a quick compare.")
            }
        }
    }

    private func similarRow(_ similar: SimilarPlayer) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 44, height: 44)
                Text("\(Int(similar.score.rounded()))")
                    .font(.caption.bold().monospacedDigit())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(similar.profile.name).font(.body.weight(.medium))
                Text("\(similar.profile.teamName) · \(similar.profile.competitionName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
