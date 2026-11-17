module CoachAnalyst
  # Post-game (single match) and team season analytics derived from StatsBomb
  # events (mirrors backend/app/analysis.py).
  module Analysis
    # Team metric descriptors used by the app's style radar.
    TEAM_METRICS = %w[
      possession passAccuracy passes progressivePasses
      finalThirdPasses shots xg goals ppda highTurnovers
    ].freeze

    module_function

    def blank
      {
        "posEvents" => 0,
        "passes" => 0, "passesCompleted" => 0, "progressivePasses" => 0, "finalThirdPasses" => 0,
        "shots" => 0, "shotsOnTarget" => 0, "xg" => 0.0, "goals" => 0,
        "pressures" => 0, "tackles" => 0, "interceptions" => 0,
        "ballRecoveries" => 0, "highTurnovers" => 0, "boxEntries" => 0
      }
    end

    def accumulate_team(event, raw)
      etype = (event["type"] || {})["name"].to_s
      location = event["location"]

      case etype
      when "Pass"
        p = event["pass"] || {}
        raw["passes"] += 1
        raw["passesCompleted"] += 1 if p["outcome"].nil?
        finish = p["end_location"]
        if finish && location
          raw["progressivePasses"] += 1 if finish[0] - location[0] >= 10
          raw["finalThirdPasses"] += 1 if finish[0] >= 80
          raw["boxEntries"] += 1 if finish[0] >= 102 && finish[1] >= 18 && finish[1] <= 62
        end
      when "Shot"
        s = event["shot"] || {}
        raw["shots"] += 1
        raw["xg"] += (s["statsbomb_xg"] || 0.0).to_f
        outcome = (s["outcome"] || {})["name"]
        raw["goals"] += 1 if outcome == "Goal"
        raw["shotsOnTarget"] += 1 if ["Goal", "Saved"].include?(outcome)
      when "Pressure"
        raw["pressures"] += 1
      when "Interception"
        raw["interceptions"] += 1
      when "Duel"
        raw["tackles"] += 1 if ((event["duel"] || {})["type"] || {})["name"] == "Tackle"
      when "Ball Recovery"
        raw["ballRecoveries"] += 1
        raw["highTurnovers"] += 1 if location && location[0] >= 60
      end
    end

    def derive(raw, opponent, total_pos)
      defensive_actions = raw["pressures"] + raw["tackles"] + raw["interceptions"]
      {
        "possession" => total_pos.positive? ? Util.py_round(100 * raw["posEvents"] / total_pos.to_f, 1) : 0.0,
        "passAccuracy" => raw["passes"].positive? ? Util.py_round(raw["passesCompleted"] / raw["passes"].to_f, 3) : 0.0,
        "passes" => raw["passes"],
        "passesCompleted" => raw["passesCompleted"],
        "progressivePasses" => raw["progressivePasses"],
        "finalThirdPasses" => raw["finalThirdPasses"],
        "boxEntries" => raw["boxEntries"],
        "shots" => raw["shots"],
        "shotsOnTarget" => raw["shotsOnTarget"],
        "xg" => Util.py_round(raw["xg"], 2),
        "goals" => raw["goals"],
        "ppda" => defensive_actions.positive? ? Util.py_round(opponent["passes"] / defensive_actions.to_f, 2) : 0.0,
        "pressures" => raw["pressures"],
        "interceptions" => raw["interceptions"],
        "tackles" => raw["tackles"],
        "highTurnovers" => raw["highTurnovers"],
        # Season-only fields, present (with neutral values) so match and season
        # payloads share one shape.
        "matches" => 1,
        "xgFor" => Util.py_round(raw["xg"], 2),
        "recent" => []
      }
    end

    def match_team_stats(events, home_id, away_id)
      raw = { home_id => blank, away_id => blank }
      events.each do |event|
        possession_team = (event["possession_team"] || {})["id"]
        raw[possession_team]["posEvents"] += 1 if raw.key?(possession_team)
        team = (event["team"] || {})["id"]
        accumulate_team(event, raw[team]) if raw.key?(team)
      end

      total_pos = raw[home_id]["posEvents"] + raw[away_id]["posEvents"]
      {
        home_id => derive(raw[home_id], raw[away_id], total_pos),
        away_id => derive(raw[away_id], raw[home_id], total_pos)
      }
    end

    def shots(events)
      events.filter_map do |event|
        next unless (event["type"] || {})["name"] == "Shot"

        s = event["shot"] || {}
        location = (event["shot"] || {})["end_location"] || event["location"] || [0, 0]
        {
          "minute" => event["minute"] || 0,
          "x" => location[0],
          "y" => location[1],
          "xg" => Util.py_round((s["statsbomb_xg"] || 0.0).to_f, 3),
          "outcome" => (s["outcome"] || {})["name"] || "Unknown",
          "teamID" => (event["team"] || {})["id"],
          "player" => (event["player"] || {})["name"] || ""
        }
      end
    end

    def momentum(events, home_id, away_id, bucket: 5)
      buckets = {}
      events.each do |event|
        next unless (event["type"] || {})["name"] == "Shot"

        minute = event["minute"] || 0
        index = (minute / bucket) * bucket
        entry = buckets[index] ||= { "minute" => index, "home" => 0.0, "away" => 0.0 }
        xg = ((event["shot"] || {})["statsbomb_xg"] || 0.0).to_f
        team_id = (event["team"] || {})["id"]
        if team_id == home_id
          entry["home"] += xg
        elsif team_id == away_id
          entry["away"] += xg
        end
      end
      buckets.sort_by { |key, _| key }.map do |_, v|
        { "minute" => v["minute"], "home" => Util.py_round(v["home"], 2), "away" => Util.py_round(v["away"], 2) }
      end
    end

    def player_ratings(events, lineups, team_id)
      rated = Aggregate.contributions(events, lineups).filter_map do |contribution|
        next unless contribution["teamID"] == team_id

        totals = contribution["totals"]
        impact = (
          totals["goals"] * 3.0 + totals["xg"] * 2.0 + totals["assists"] * 2.0 +
          totals["keyPasses"] * 0.6 + totals["progressivePasses"] * 0.06 +
          totals["pressures"] * 0.02
        )
        {
          "playerID" => "sb-#{contribution['playerID']}",
          "name" => contribution["name"],
          "minutes" => Util.py_round(contribution["minutes"]),
          "goals" => totals["goals"].to_i,
          "assists" => totals["assists"].to_i,
          "xg" => Util.py_round(totals["xg"], 2),
          "keyPasses" => totals["keyPasses"].to_i,
          "impact" => Util.py_round(impact, 1)
        }
      end
      Util.stable_sort(rated) { |a, b| b["impact"] <=> a["impact"] }
    end

    def aggregate_season(match_stats, recent)
      count = [match_stats.length, 1].max

      average = ->(key) { match_stats.sum { |s| s.fetch(key, 0.0) } / count.to_f }

      {
        "matches" => match_stats.length,
        "possession" => Util.py_round(average.call("possession"), 1),
        "passAccuracy" => Util.py_round(average.call("passAccuracy"), 3),
        "passes" => Util.py_round(average.call("passes"), 1),
        "progressivePasses" => Util.py_round(average.call("progressivePasses"), 1),
        "finalThirdPasses" => Util.py_round(average.call("finalThirdPasses"), 1),
        "boxEntries" => Util.py_round(average.call("boxEntries"), 1),
        "shots" => Util.py_round(average.call("shots"), 1),
        "shotsOnTarget" => Util.py_round(average.call("shotsOnTarget"), 1),
        "xg" => Util.py_round(average.call("xg"), 2),
        "goals" => Util.py_round(average.call("goals"), 2),
        "ppda" => Util.py_round(average.call("ppda"), 2),
        "pressures" => Util.py_round(average.call("pressures"), 1),
        "interceptions" => Util.py_round(average.call("interceptions"), 1),
        "tackles" => Util.py_round(average.call("tackles"), 1),
        "highTurnovers" => Util.py_round(average.call("highTurnovers"), 1),
        "xgFor" => Util.py_round(match_stats.sum { |s| s.fetch("xg", 0.0) }, 1),
        "recent" => Util.stable_sort(recent) { |a, b| a["date"] <=> b["date"] }.last(6)
      }
    end

    # Per-team season aggregates for a whole competition, cached on disk.
    def team_season_stats(client, competition_id, season_id, force: false, max_matches: Builder.default_max_matches)
      path = Builder.team_cache_path(competition_id, season_id)
      return JSON.parse(path.read) if !force && path.exist?

      matches = client.matches(competition_id, season_id).first(max_matches)
      per_team = {}
      recent = {}

      matches.each_slice(Builder::CHUNK) do |chunk|
        threads = chunk.map do |match|
          Thread.new { [match, client.events(match["match_id"])] }
        end

        threads.map(&:value).each do |match, events|
          home_id = match["home_team"]["home_team_id"]
          away_id = match["away_team"]["away_team_id"]
          stats = match_team_stats(events, home_id, away_id)
          [[home_id, away_id], [away_id, home_id]].each do |team_id, opponent_id|
            per_team[team_id.to_s] ||= []
            per_team[team_id.to_s] << stats[team_id]
            is_home = team_id == home_id
            recent[team_id.to_s] ||= []
            recent[team_id.to_s] << {
              "opponent" => (is_home ? match["away_team"] : match["home_team"])["#{is_home ? 'away' : 'home'}_team_name"],
              "home" => is_home,
              "goalsFor" => is_home ? match["home_score"] : match["away_score"],
              "goalsAgainst" => is_home ? match["away_score"] : match["home_score"],
              "xg" => stats[team_id]["xg"],
              "date" => match["match_date"]
            }
          end
        end
      end

      data = per_team.each_with_object({}) do |(team_id, stats), hash|
        hash[team_id] = aggregate_season(stats, recent.fetch(team_id, []))
      end
      begin
        Storage.write_json_atomic(path, data)
      rescue SystemCallError
        # Cache write is best-effort.
      end
      data
    end
  end
end
