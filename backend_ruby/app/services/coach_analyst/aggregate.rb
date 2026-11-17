module CoachAnalyst
  # Turn StatsBomb lineups + events into per-player metric totals.
  #
  # Faithful port of `backend/app/aggregate.py` (itself a port of the Swift
  # `StatsBombAggregator`) so the Ruby and Python backends agree to the digit.
  module Aggregate
    TOTAL_KEYS = %w[
      minutes goals xg shots assists keyPasses
      passesAttempted passesCompleted progressivePasses finalThirdPasses
      carries progressiveCarries dribblesCompleted
      tacklesWon interceptions clearances ballRecoveries
      pressures touchesInBox saves
    ].freeze

    module_function

    def empty_totals(minutes = 0.0)
      totals = TOTAL_KEYS.each_with_object({}) { |key, hash| hash[key] = 0.0 }
      totals["minutes"] = minutes.to_f
      totals
    end

    def parse_clock(clock)
      parts = clock.to_s.split(":")
      return 0.0 unless parts.length == 2

      Integer(parts[0]) + Integer(parts[1]) / 60.0
    end

    def position_minutes(positions, match_length)
      total = 0.0
      by_position = {}
      positions.each do |position|
        start = parse_clock(position["from"] || "00:00")
        finish = position["to"] ? parse_clock(position["to"]) : match_length
        duration = [0.0, finish - start].max
        total += duration
        name = position["position"] || "Unknown"
        by_position[name] = by_position.fetch(name, 0.0) + duration
      end
      primary = by_position.empty? ? "Unknown" : Util.max_key(by_position)
      [total, primary]
    end

    def position_group(position_name)
      name = position_name.to_s.downcase
      return "Goalkeeper" if name.include?("goalkeeper")
      return "Defender" if name.include?("back")
      return "Midfielder" if name.include?("midfield")
      return "Forward" if name.include?("wing")
      return "Forward" if name.include?("forward") || name.include?("striker")

      "Midfielder"
    end

    def in_box(location)
      !location.nil? && location.length >= 2 && location[0] >= 102 && location[1] >= 18 && location[1] <= 62
    end

    def accumulate(event, assist_ids, totals)
      etype = (event["type"] || {})["name"].to_s
      location = event["location"]
      inside = in_box(location)

      case etype
      when "Pass"
        p = event["pass"] || {}
        totals["passesAttempted"] += 1
        totals["passesCompleted"] += 1 if p["outcome"].nil?
        finish = p["end_location"]
        if finish && location
          totals["progressivePasses"] += 1 if finish[0] - location[0] >= 10
          totals["finalThirdPasses"] += 1 if finish[0] >= 80
        end
        totals["keyPasses"] += 1 if p["assisted_shot_id"]
        totals["assists"] += 1 if p["goal_assist"] || assist_ids.include?(event["id"])
        totals["touchesInBox"] += 1 if inside
      when "Shot"
        s = event["shot"] || {}
        totals["shots"] += 1
        totals["xg"] += (s["statsbomb_xg"] || 0.0).to_f
        totals["goals"] += 1 if (s["outcome"] || {})["name"] == "Goal"
        totals["touchesInBox"] += 1 if inside
      when "Carry"
        c = event["carry"] || {}
        totals["carries"] += 1
        finish = c["end_location"]
        totals["progressiveCarries"] += 1 if finish && location && finish[0] - location[0] >= 10
        totals["touchesInBox"] += 1 if inside
      when "Dribble"
        totals["dribblesCompleted"] += 1 if ((event["dribble"] || {})["outcome"] || {})["name"] == "Complete"
      when "Duel"
        d = event["duel"] || {}
        dtype = (d["type"] || {})["name"].to_s
        outcome = (d["outcome"] || {})["name"].to_s
        totals["tacklesWon"] += 1 if dtype == "Tackle" && ["Won", "Success In Play"].include?(outcome)
      when "Interception"
        totals["interceptions"] += 1
      when "Clearance"
        totals["clearances"] += 1
      when "Ball Recovery"
        totals["ballRecoveries"] += 1
      when "Pressure"
        totals["pressures"] += 1
      when "Goal Keeper"
        totals["saves"] += 1 if ((event["goalkeeper"] || {})["type"] || {})["name"].to_s.include?("Saved")
      end
    end

    def contributions(events, lineups)
      minutes = events.map { |e| e["minute"] || 0 }
      match_length = (minutes.empty? ? 90 : minutes.max).to_f
      by_player = {}

      lineups.each do |team|
        (team["lineup"] || []).each do |player|
          minutes, best_position = position_minutes(player["positions"] || [], match_length)
          by_player[player["player_id"]] = {
            "playerID" => player["player_id"],
            "name" => player["player_nickname"] || player["player_name"] || "",
            "teamID" => team["team_id"],
            "teamName" => team["team_name"],
            "minutes" => minutes,
            "positionName" => best_position,
            "group" => position_group(best_position),
            "totals" => empty_totals(minutes)
          }
        end
      end

      assist_ids = events.filter_map do |event|
        next unless (event["type"] || {})["name"] == "Shot"

        shot = event["shot"] || {}
        shot["key_pass_id"] if (shot["outcome"] || {})["name"] == "Goal" && shot["key_pass_id"]
      end.to_set

      events.each do |event|
        player = event["player"]
        next unless player

        pid = player["id"]
        contribution = by_player[pid] || {
          "playerID" => pid,
          "name" => player["name"] || "",
          "teamID" => (event["team"] || {})["id"],
          "teamName" => (event["team"] || {})["name"],
          "minutes" => 0.0,
          "positionName" => "Unknown",
          "group" => "Midfielder",
          "totals" => empty_totals(0.0)
        }
        accumulate(event, assist_ids, contribution["totals"])
        by_player[pid] = contribution
      end

      by_player.values
    end
  end
end
