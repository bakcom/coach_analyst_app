# Computes the same analytics as parity/run_python.py using the Ruby port.
# Loaded by the `parity:run` rake task (which has the Rails environment ready).
module Parity
  module RubyRunner
    module_function

    def compute(data)
      events = data["events"]
      lineups = data["lineups"]
      home_id = data["home_id"]
      away_id = data["away_id"]

      team_stats = CoachAnalyst::Analysis.match_team_stats(events, home_id, away_id)
      stringified = team_stats.each_with_object({}) { |(key, value), hash| hash[key.to_s] = value }

      {
        "contributions" => CoachAnalyst::Aggregate.contributions(events, lineups),
        "team_stats" => stringified,
        "shots" => CoachAnalyst::Analysis.shots(events),
        "momentum" => CoachAnalyst::Analysis.momentum(events, home_id, away_id),
        "ratings_home" => CoachAnalyst::Analysis.player_ratings(events, lineups, home_id),
        "season" => CoachAnalyst::Analysis.aggregate_season(
          [team_stats[home_id], team_stats[away_id]], data["recent"]
        ),
        "similar" => CoachAnalyst::Metrics.similar(
          data["target"], data["pool"], other_competitions_only: true, limit: 5, min_minutes: 0.0
        ),
        "comparison" => CoachAnalyst::Metrics.comparison(
          data["target"], data["candidate"], data["pool"], min_minutes: 0.0
        ),
        "merged" => CoachAnalyst::Builder.merge_profiles([data["profiles_a"], data["profiles_b"]]),
        "position_groups" => data["position_names"].each_with_object({}) do |name, hash|
          hash[name] = CoachAnalyst::Aggregate.position_group(name)
        end
      }
    end
  end

  # Deep JSON comparison with a float tolerance, reporting every difference.
  module Compare
    module_function

    def diffs(a, b, path = "$", tol: 1e-9, out: [])
      case [a, b]
      when ->(pair) { pair.all? { |v| v.is_a?(Hash) } }
        (a.keys | b.keys).each do |key|
          if !a.key?(key)
            out << "#{path}.#{key}: only in ruby"
          elsif !b.key?(key)
            out << "#{path}.#{key}: only in python"
          else
            diffs(a[key], b[key], "#{path}.#{key}", tol: tol, out: out)
          end
        end
      when ->(pair) { pair.all? { |v| v.is_a?(Array) } }
        if a.length != b.length
          out << "#{path}: length python=#{a.length} ruby=#{b.length}"
        else
          a.each_index { |i| diffs(a[i], b[i], "#{path}[#{i}]", tol: tol, out: out) }
        end
      when ->(pair) { pair.all? { |v| v.is_a?(Numeric) } }
        scale = [1.0, a.to_f.abs, b.to_f.abs].max
        out << "#{path}: python=#{a} ruby=#{b}" if (a.to_f - b.to_f).abs > tol * scale
      else
        out << "#{path}: python=#{a.inspect} ruby=#{b.inspect}" unless a == b
      end
      out
    end
  end
end
