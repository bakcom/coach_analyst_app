module CoachAnalyst
  # Metric definitions, profile aggregation and the position-aware similarity
  # and comparison maths (mirrors backend/app/metrics.py, itself ported from the
  # Swift `ScoutMetric` / `SimilarityEngine`).
  module Metrics
    METRICS_BY_GROUP = {
      "Goalkeeper" => %w[saves passAccuracy passesAttempted ballRecoveries],
      "Defender" => %w[tacklesWon interceptions clearances ballRecoveries
                       passAccuracy progressivePasses pressures passesAttempted],
      "Midfielder" => %w[passesAttempted passAccuracy progressivePasses finalThirdPasses
                         keyPasses carries progressiveCarries dribblesCompleted
                         interceptions pressures ballRecoveries],
      "Forward" => %w[goals xg shots assists keyPasses
                      dribblesCompleted touchesInBox progressiveCarries pressures]
    }.freeze

    module_function

    def metrics_for(group)
      METRICS_BY_GROUP.fetch(group, METRICS_BY_GROUP["Midfielder"])
    end

    def metric_value(metric, totals, minutes)
      if metric == "passAccuracy"
        attempted = totals.fetch("passesAttempted", 0.0)
        return attempted.positive? ? totals.fetch("passesCompleted", 0.0) / attempted.to_f : 0.0
      end
      return 0.0 if minutes <= 0

      totals.fetch(metric, 0.0) / minutes.to_f * 90.0
    end

    def add_totals(target, source)
      Aggregate::TOTAL_KEYS.each do |key|
        target[key] = target.fetch(key, 0.0) + source.fetch(key, 0.0)
      end
    end

    # Merges a player's contributions across matches and competitions.
    class Accumulator
      attr_reader :player_id

      def initialize(player_id, name, team_name)
        @player_id = player_id
        @name = name
        @team_name = team_name
        @totals = Aggregate.empty_totals(0.0)
        @minutes_by_group = {}
        @minutes_by_competition = {}
        @name_by_competition = {}
        @minutes_by_position = {}
      end

      def add(contribution, competition_id, competition_name)
        @name = contribution["name"]
        @team_name = contribution["teamName"]
        Metrics.add_totals(@totals, contribution["totals"])
        minutes = contribution["minutes"]
        group = contribution["group"]
        @minutes_by_group[group] = @minutes_by_group.fetch(group, 0.0) + minutes
        @minutes_by_competition[competition_id] = @minutes_by_competition.fetch(competition_id, 0.0) + minutes
        @name_by_competition[competition_id] = competition_name
        position = contribution["positionName"]
        @minutes_by_position[position] = @minutes_by_position.fetch(position, 0.0) + minutes
      end

      def profile
        group = @minutes_by_group.empty? ? "Midfielder" : Util.max_key(@minutes_by_group)
        comp_id = @minutes_by_competition.empty? ? 0 : Util.max_key(@minutes_by_competition)
        position = @minutes_by_position.empty? ? "Unknown" : Util.max_key(@minutes_by_position)
        {
          "playerID" => "sb-#{@player_id}",
          "name" => @name,
          "teamName" => @team_name,
          "competitionID" => comp_id,
          "competitionName" => @name_by_competition.fetch(comp_id, ""),
          "group" => group,
          "primaryPosition" => position,
          "totals" => @totals
        }
      end
    end

    def build_profiles(match_contributions, competition_id, competition_name, team_id = nil)
      by_player = {}
      match_contributions.each do |match|
        match.each do |contribution|
          next if team_id && contribution["teamID"] != team_id

          acc = by_player[contribution["playerID"]] ||
                Accumulator.new(contribution["playerID"], contribution["name"], contribution["teamName"])
          acc.add(contribution, competition_id, competition_name)
          by_player[contribution["playerID"]] = acc
        end
      end
      by_player.values.map(&:profile)
    end

    # MARK: - Similarity

    def similar(target, pool, other_competitions_only: true, limit: 10, min_minutes: 270.0)
      metrics = metrics_for(target["group"])

      candidates = lambda do |threshold|
        pool.select do |p|
          p["playerID"] != target["playerID"] &&
            p["group"] == target["group"] &&
            p["totals"].fetch("minutes", 0.0) >= threshold &&
            (!other_competitions_only || p["competitionID"] != target["competitionID"])
        end
      end

      population = candidates.call(min_minutes)
      population = candidates.call(min_minutes / 2) if population.length < 5
      population = candidates.call(0.0) if population.length < 5

      return { "similar" => [], "populationSize" => 0 } if population.empty?

      target_vec = metrics.map { |m| metric_value(m, target["totals"], target["totals"].fetch("minutes", 0.0)) }
      pop_vecs = population.map do |p|
        metrics.map { |m| metric_value(m, p["totals"], p["totals"].fetch("minutes", 0.0)) }
      end

      all_vecs = pop_vecs + [target_vec]
      means = []
      stds = []
      metrics.each_index do |i|
        column = all_vecs.map { |v| v[i] }
        mean = column.sum / column.length.to_f
        variance = column.sum { |x| (x - mean)**2 } / column.length.to_f
        means << mean
        stds << [Math.sqrt(variance), 1e-6].max
      end

      target_z = metrics.each_index.map { |i| (target_vec[i] - means[i]) / stds[i] }

      scored = population.each_with_index.map do |p, index|
        vec = pop_vecs[index]
        distance = Math.sqrt(
          metrics.each_index.sum do |i|
            (((vec[i] - means[i]) / stds[i]) - target_z[i])**2
          end
        )
        normalised = distance / Math.sqrt(metrics.length)
        { "profile" => p, "score" => 100.0 * Math.exp(-normalised) }
      end

      scored = Util.stable_sort(scored) { |a, b| b["score"] <=> a["score"] }
      { "similar" => scored.first(limit), "populationSize" => population.length }
    end

    def comparison(target, candidate, pool, min_minutes: 270.0)
      metrics = metrics_for(target["group"])

      reference = lambda do |metric|
        values = pool.select { |p| p["group"] == target["group"] && p["totals"].fetch("minutes", 0.0) >= min_minutes }
                     .map { |p| metric_value(metric, p["totals"], p["totals"].fetch("minutes", 0.0)) }
        if values.length < 5
          values = pool.select { |p| p["group"] == target["group"] }
                       .map { |p| metric_value(metric, p["totals"], p["totals"].fetch("minutes", 0.0)) }
        end
        values
      end

      percentile = lambda do |value, values|
        return 0.5 if values.length < 2

        values.count { |v| v <= value } / values.length.to_f
      end

      metrics.map do |metric|
        reference_values = reference.call(metric)
        t_val = metric_value(metric, target["totals"], target["totals"].fetch("minutes", 0.0))
        c_val = metric_value(metric, candidate["totals"], candidate["totals"].fetch("minutes", 0.0))
        average = reference_values.empty? ? 0.0 : reference_values.sum / reference_values.length.to_f
        {
          "metric" => metric,
          "targetValue" => t_val,
          "candidateValue" => c_val,
          "targetNormalized" => percentile.call(t_val, reference_values),
          "candidateNormalized" => percentile.call(c_val, reference_values),
          "populationAverage" => average
        }
      end
    end
  end
end
