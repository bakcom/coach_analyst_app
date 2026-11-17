import Foundation

/// Position-aware similarity. Players are compared only against others in the
/// same `PositionGroup`, on that role's metric set, using z-scored per-90
/// values so no single metric dominates by scale.
enum SimilarityEngine {

    struct Result: Codable {
        var similar: [SimilarPlayer]
        var populationSize: Int
    }

    static func similar(
        to target: PlayerMetricProfile,
        pool: [PlayerMetricProfile],
        otherCompetitionsOnly: Bool = true,
        limit: Int = 10,
        minMinutes: Double = 270
    ) -> Result {
        let metrics = ScoutMetric.metrics(for: target.group)

        func candidates(minMinutes: Double) -> [PlayerMetricProfile] {
            pool.filter { candidate in
                guard candidate.playerID != target.playerID,
                      candidate.group == target.group,
                      candidate.minutes >= minMinutes else { return false }
                return !otherCompetitionsOnly || candidate.competitionID != target.competitionID
            }
        }

        var population = candidates(minMinutes: minMinutes)
        if population.count < 5 { population = candidates(minMinutes: minMinutes / 2) }
        if population.count < 5 { population = candidates(minMinutes: 0) }

        guard !population.isEmpty else { return Result(similar: [], populationSize: 0) }

        // Target vector + population vectors.
        let targetVec = metrics.map { target.value($0) }
        let popVecs = population.map { profile in metrics.map { profile.value($0) } }

        // z-score normalisation using the population (target included in stats).
        let all = popVecs + [targetVec]
        var means = [Double](repeating: 0, count: metrics.count)
        var stds = [Double](repeating: 1, count: metrics.count)
        for m in metrics.indices {
            let column = all.map { $0[m] }
            let mean = column.reduce(0, +) / Double(column.count)
            let variance = column.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(column.count)
            means[m] = mean
            stds[m] = max(sqrt(variance), 1e-6)
        }

        let targetZ = zip(targetVec, metrics.indices).map { ($0 - means[$1]) / stds[$1] }

        let scored: [SimilarPlayer] = population.map { profile in
            let vec = metrics.map { profile.value($0) }
            let distance = sqrt(zip(vec, metrics.indices).reduce(0.0) { partial, pair in
                let z = (pair.0 - means[pair.1]) / stds[pair.1]
                let d = z - targetZ[pair.1]
                return partial + d * d
            })
            let normalised = distance / sqrt(Double(metrics.count))
            let score = 100 * exp(-normalised)
            return SimilarPlayer(profile: profile, score: score)
        }
        .sorted { $0.score > $1.score }

        return Result(similar: Array(scored.prefix(limit)), populationSize: population.count)
    }

    /// Builds a per-metric head-to-head between two players, normalising each
    /// axis to a 0...1 percentile within the pool population so both can be
    /// drawn on one radar.
    static func comparison(
        target: PlayerMetricProfile,
        candidate: PlayerMetricProfile,
        population: [PlayerMetricProfile],
        minMinutes: Double = 270
    ) -> [MetricComparison] {
        let metrics = ScoutMetric.metrics(for: target.group)

        func referenceValues(for metric: ScoutMetric) -> [Double] {
            var values = population
                .filter { $0.group == target.group && $0.minutes >= minMinutes }
                .map { $0.value(metric) }
            if values.count < 5 {
                values = population.filter { $0.group == target.group }.map { $0.value(metric) }
            }
            return values
        }

        return metrics.map { metric in
            let reference = referenceValues(for: metric)
            let targetValue = target.value(metric)
            let candidateValue = candidate.value(metric)
            let average = reference.isEmpty ? 0 : reference.reduce(0, +) / Double(reference.count)
            return MetricComparison(
                metric: metric,
                targetValue: targetValue,
                candidateValue: candidateValue,
                targetNormalized: percentile(targetValue, in: reference),
                candidateNormalized: percentile(candidateValue, in: reference),
                populationAverage: average
            )
        }
    }

    /// Fraction of the reference population at or below `value`, in 0...1.
    private static func percentile(_ value: Double, in reference: [Double]) -> Double {
        guard reference.count >= 2 else { return 0.5 }
        let below = reference.filter { $0 <= value }.count
        return Double(below) / Double(reference.count)
    }
}
