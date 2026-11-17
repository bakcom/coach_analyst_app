module CoachAnalyst
  # Shared, stateless build logic used by both the API process and the queue
  # worker (mirrors backend/app/builder.py): per-competition aggregation with an
  # incremental disk cache, and the merge step that produces the pooled list.
  module Builder
    CHUNK = 6

    module_function

    def pool_cache_dir
      Config.cache_dir.join("pool_cache")
    end

    def team_cache_dir
      Config.cache_dir.join("team_cache")
    end

    def default_max_matches
      Config.max_matches_per_competition
    end

    def competition_cache_path(competition_id, season_id)
      pool_cache_dir.join("#{competition_id}-#{season_id}.json")
    end

    def team_cache_path(competition_id, season_id)
      team_cache_dir.join("#{competition_id}-#{season_id}.json")
    end

    # Merge per-competition profiles, combining players who appear in more than
    # one competition and attributing each to the competition (and role) they
    # played most in.
    def merge_profiles(profile_lists)
      accs = {}
      profile_lists.each do |profiles|
        profiles.each do |profile|
          acc = accs[profile["playerID"]]
          if acc.nil?
            acc = {
              "name" => profile["name"],
              "teamName" => profile["teamName"],
              "position" => profile["primaryPosition"],
              "best_position_minutes" => -1.0,
              "totals" => Aggregate::TOTAL_KEYS.each_with_object({}) { |key, hash| hash[key] = 0.0 },
              "competition_minutes" => {},
              "competition_names" => {},
              "group_minutes" => {}
            }
            accs[profile["playerID"]] = acc
          end

          Metrics.add_totals(acc["totals"], profile["totals"])
          minutes = profile["totals"].fetch("minutes", 0.0)
          comp_id = profile["competitionID"]
          acc["competition_minutes"][comp_id] = acc["competition_minutes"].fetch(comp_id, 0.0) + minutes
          acc["competition_names"][comp_id] = profile["competitionName"]
          group = profile["group"]
          acc["group_minutes"][group] = acc["group_minutes"].fetch(group, 0.0) + minutes
          if minutes >= acc["best_position_minutes"]
            acc["best_position_minutes"] = minutes
            acc["position"] = profile["primaryPosition"]
            acc["name"] = profile["name"]
            acc["teamName"] = profile["teamName"]
          end
        end
      end

      accs.map do |player_id, acc|
        comp_id = Util.max_key(acc["competition_minutes"])
        group = Util.max_key(acc["group_minutes"])
        {
          "playerID" => player_id,
          "name" => acc["name"],
          "teamName" => acc["teamName"],
          "competitionID" => comp_id,
          "competitionName" => acc["competition_names"].fetch(comp_id, ""),
          "group" => group,
          "primaryPosition" => acc["position"],
          "totals" => acc["totals"]
        }
      end
    end

    def analyze_matches(client, match_ids, progress = nil)
      results = []
      total = [match_ids.length, 1].max
      match_ids.each_slice(CHUNK) do |chunk|
        threads = chunk.map do |match_id|
          Thread.new do
            lineups = client.lineups(match_id)
            events = client.events(match_id)
            Aggregate.contributions(events, lineups)
          end
        end
        results.concat(threads.map(&:value))
        progress&.call([results.length, total].min.to_f / total)
      end
      results
    end

    # All player profiles for a competition season, from cache when present.
    def ensure_competition_profiles(client, competition_id, season_id, name, force: false, progress: nil,
                                    max_matches: default_max_matches)
      path = competition_cache_path(competition_id, season_id)
      if !force && path.exist?
        progress&.call(1.0)
        return JSON.parse(path.read)
      end

      matches = client.matches(competition_id, season_id)
      match_ids = matches.map { |m| m["match_id"] }.first(max_matches)
      results = analyze_matches(client, match_ids, progress)
      profiles = Metrics.build_profiles(results, competition_id, name)
      begin
        Storage.write_json_atomic(path, profiles)
      rescue SystemCallError
        # Cache write is best-effort.
      end
      profiles
    end

    def build_pool_profiles(client, selections, force: false, progress: nil, max_matches: default_max_matches)
      count = [selections.length, 1].max
      profile_lists = []
      selections.each_with_index do |selection, index|
        competition_id = selection["competitionID"]
        season_id = selection["seasonID"]
        name = selection["name"] || "#{competition_id}/#{season_id}"

        report = lambda do |fraction|
          next unless progress

          prefix = if competition_cache_path(competition_id, season_id).exist? && !force
                     "Loading "
                   else
                     "Analysing "
                   end
          progress.call((index + fraction) / count, prefix + name)
        end

        profile_lists << ensure_competition_profiles(
          client, competition_id, season_id, name, force: force, progress: report, max_matches: max_matches
        )
      end
      merge_profiles(profile_lists)
    end
  end
end
