import SwiftUI

/// The comparison body (radar + legend + table), used both by the pushed
/// screen and by the swipe-in panel over a player profile.
struct ComparisonContent: View {
    let target: PlayerMetricProfile
    let candidate: PlayerMetricProfile
    var showsClose: Bool = false
    var onClose: (() -> Void)?

    @Environment(ScoutingStore.self) private var store
    @State private var rows: [MetricComparison] = []

    private let targetColor = Color.accentColor
    private let candidateColor = Color.orange

    var body: some View {
        Group {
            if rows.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Comparing…").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scroll
            }
        }
        .task(id: "\(target.playerID)-\(candidate.playerID)") {
            rows = await store.comparison(target: target, candidate: candidate)
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if showsClose { panelHeader }
                playersHeader
                radarCard
                legend
                metricsTable
            }
            .padding()
        }
    }

    private var panelHeader: some View {
        HStack {
            Text("Comparison").font(.headline)
            Spacer()
            Button {
                onClose?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var playersHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            playerCard(target, color: targetColor, label: "Target")
            playerCard(candidate, color: candidateColor, label: "Similar")
        }
    }

    private func playerCard(_ profile: PlayerMetricProfile, color: Color, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2.bold()).foregroundStyle(color)
            Text(profile.name).font(.subheadline.bold()).lineLimit(2)
            Text(profile.teamName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(profile.competitionName).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            Text("\(Int(profile.minutes))′ · \(profile.group.short)")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private var radarCard: some View {
        RadarChart(
            axes: rows.map { $0.metric.shortTitle },
            series: [
                .init(name: "Target", color: targetColor, values: rows.map(\.targetNormalized)),
                .init(name: "Similar", color: candidateColor, values: rows.map(\.candidateNormalized))
            ]
        )
        .frame(height: 320)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var legend: some View {
        HStack(spacing: 20) {
            legendItem(targetColor, "\(target.name) (\(target.group.short))")
            legendItem(candidateColor, candidate.name)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).lineLimit(1)
        }
    }

    private var metricsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Metric").font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
                Text("Target").font(.caption.bold()).foregroundStyle(targetColor).frame(width: 74, alignment: .trailing)
                Text("Similar").font(.caption.bold()).foregroundStyle(candidateColor).frame(width: 74, alignment: .trailing)
            }
            .padding(.vertical, 8)

            Divider()

            ForEach(rows) { row in
                HStack {
                    Text(row.metric.title).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    valueCell(row.metric.display(row.targetValue), highlight: row.higher == .target, color: targetColor)
                    valueCell(row.metric.display(row.candidateValue), highlight: row.higher == .candidate, color: candidateColor)
                }
                .padding(.vertical, 7)
                Divider()
            }
        }
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func valueCell(_ text: String, highlight: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            if highlight { Circle().fill(color).frame(width: 6, height: 6) }
            Text(text).font(.subheadline.monospacedDigit())
        }
        .frame(width: 74, alignment: .trailing)
    }
}

/// Full-screen pushed comparison.
struct ScoutComparisonView: View {
    let target: PlayerMetricProfile
    let candidate: PlayerMetricProfile

    var body: some View {
        ComparisonContent(target: target, candidate: candidate)
            .navigationTitle("Comparison")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Overlay that slides the comparison in from the trailing edge, leaving the
/// profile it was opened from in place underneath.
struct ComparisonPanel: View {
    let target: PlayerMetricProfile
    let candidate: PlayerMetricProfile
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            ComparisonContent(target: target, candidate: candidate, showsClose: true, onClose: onClose)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .shadow(radius: 12)
        }
    }
}
