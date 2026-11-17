require "date"

module CoachAnalyst
  # High-level scouting service: catalog, per-club datasets, the pooled player
  # list and analytics (mirrors backend/app/service.py).
  #
  # Pool builds run on a durable Redis queue when available (surviving restarts);
  # otherwise they fall back to an in-process background thread.
  class Service
    def initialize(client, max_matches: Config.max_matches_per_competition)
      @client = client
      @max_matches = max_matches
      @pool = []
      @pool_mtime = -1.0
      @job = { "jobId" => "inline", "status" => "idle", "progress" => 0.0, "message" => "", "playerCount" => 0 }
      @job_thread = nil
    end

    attr_reader :client, :max_matches

    def pool_file
      Config.cache_dir.join("pool.json")
    end

    # MARK: - Pool storage

    def current_pool
      mtime = File.mtime(pool_file).to_f
    rescue Errno::ENOENT
      return @pool
    else
      if mtime != @pool_mtime
        begin
          @pool = JSON.parse(pool_file.read)
          @pool_mtime = mtime
        rescue Errno::ENOENT, JSON::ParserError
          # Keep the last good pool.
        end
      end
      @pool
    end

    def pool_count
      current_pool.length
    end

    # MARK: - Catalog

    def competitions
      raw = @client.competitions
      comps = raw.map do |c|
        {
          "competitionID" => c["competition_id"],
          "seasonID" => c["season_id"],
          "name" => c["competition_name"],
          "country" => c["country_name"],
          "gender" => c["competition_gender"],
          "seasonName" => c["season_name"]
        }
      end
      Util.stable_sort(comps) do |a, b|
        (a["country"] <=> b["country"]).nonzero? ||
          (a["name"] <=> b["name"]).nonzero? ||
          (a["seasonName"] <=> b["seasonName"]) || 0
      end
    end

    def fixtures(competition_id, season_id)
      raw = @client.matches(competition_id, season_id)
      fixtures = raw.map do |m|
        date = Date.iso8601(m["match_date"])
        {
          "id" => m["match_id"],
          "date" => "#{date.iso8601}T00:00:00+00:00",
          "home" => team(m["home_team"]["home_team_id"], m["home_team"]["home_team_name"]),
          "away" => team(m["away_team"]["away_team_id"], m["away_team"]["away_team_name"]),
          "homeScore" => m["home_score"],
          "awayScore" => m["away_score"]
        }
      end
      Util.stable_sort(fixtures) { |a, b| b["date"] <=> a["date"] }
    end

    def teams(competition_id, season_id)
      seen = {}
      fixtures(competition_id, season_id).each do |f|
        seen[f["home"]["id"]] = f["home"]
        seen[f["away"]["id"]] = f["away"]
      end
      Util.stable_sort(seen.values) { |a, b| a["name"] <=> b["name"] }
    end

    # MARK: - Datasets

    def dataset(competition_id, season_id, competition_name, team_id)
      fixtures = fixtures(competition_id, season_id)
      team_fixtures = fixtures.select do |f|
        f["home"]["id"] == "sb-#{team_id}" || f["away"]["id"] == "sb-#{team_id}"
      end
      team = find_team(team_fixtures, team_id)
      profiles = Builder.ensure_competition_profiles(
        @client, competition_id, season_id, competition_name, max_matches: @max_matches
      )
      players = profiles.select { |p| p["teamName"] == team["name"] }
      players = Util.stable_sort(players) { |a, b| b["totals"]["minutes"] <=> a["totals"]["minutes"] }
      {
        "team" => team,
        "competition" => competition(competition_id, season_id, competition_name),
        "fixtures" => team_fixtures,
        "players" => players
      }
    end

    # MARK: - Analytics

    def match_analysis(competition_id, season_id, match_id)
      fixtures = fixtures(competition_id, season_id)
      meta = fixtures.find { |f| f["id"] == match_id }
      raise LookupError, "Match not found in this competition season." if meta.nil?

      events = @client.events(match_id)
      lineups = @client.lineups(match_id)
      home_id = team_id(meta["home"]["id"])
      away_id = team_id(meta["away"]["id"])
      stats = Analysis.match_team_stats(events, home_id, away_id)

      {
        "match" => meta,
        "home" => {
          "team" => meta["home"],
          "stats" => stats[home_id],
          "players" => Analysis.player_ratings(events, lineups, home_id)
        },
        "away" => {
          "team" => meta["away"],
          "stats" => stats[away_id],
          "players" => Analysis.player_ratings(events, lineups, away_id)
        },
        "shots" => Analysis.shots(events),
        "momentum" => Analysis.momentum(events, home_id, away_id)
      }
    end

    def team_analysis(competition_id, season_id, competition_name, team_id)
      fixtures = fixtures(competition_id, season_id)
      team_fixtures = fixtures.select do |f|
        f["home"]["id"] == "sb-#{team_id}" || f["away"]["id"] == "sb-#{team_id}"
      end
      team = find_team(team_fixtures, team_id)
      season_stats = Analysis.team_season_stats(@client, competition_id, season_id, max_matches: @max_matches)
      profiles = Builder.ensure_competition_profiles(
        @client, competition_id, season_id, competition_name, max_matches: @max_matches
      )
      squad = profiles.select { |p| p["teamName"] == team["name"] }
      squad = Util.stable_sort(squad) { |a, b| b["totals"]["minutes"] <=> a["totals"]["minutes"] }

      {
        "team" => team,
        "competition" => competition(competition_id, season_id, competition_name),
        "stats" => season_stats.fetch(team_id.to_s, {}),
        "players" => squad.first(12),
        "fixtures" => team_fixtures
      }
    end

    # MARK: - Background pool job

    def start_build(selections, force: false)
      if TaskQueue.redis_available?
        job_id = TaskQueue.enqueue("build_pool", [selections, force])
        @job = { "jobId" => job_id, "status" => "queued", "progress" => 0.0, "message" => "Queued…", "playerCount" => pool_count }
        return @job
      end

      @job_thread.kill if @job_thread&.alive?
      @job = { "jobId" => "inline", "status" => "running", "progress" => 0.0, "message" => "Starting…", "playerCount" => pool_count }
      @job_thread = Thread.new { run_inline(selections, force) }
      @job
    end

    def run_inline(selections, force)
      progress = ->(fraction, message) do
        @job["progress"] = fraction
        @job["message"] = message
      end

      profiles = Builder.build_pool_profiles(@client, selections, force: force, progress: progress, max_matches: @max_matches)
      Storage.write_json_atomic(pool_file, profiles)
      @job.merge!(
        "status" => "ready", "progress" => 1.0, "message" => "Pool ready · #{profiles.length} players",
        "playerCount" => profiles.length
      )
    rescue StandardError => e
      @job.merge!("status" => "failed", "message" => e.message)
    end

    def job_status(job_id = nil)
      if job_id.nil? || job_id == "inline"
        @job["playerCount"] = pool_count if @job["status"] == "ready"
        return @job
      end

      meta = TaskQueue.fetch(job_id)
      if meta.nil?
        return { "jobId" => job_id, "status" => "idle", "progress" => 0.0, "message" => "Unknown job",
                 "playerCount" => pool_count }
      end

      status = meta["status"] || "running"
      result = {
        "jobId" => job_id,
        "status" => status,
        "progress" => meta.fetch("progress", status == "ready" ? 1.0 : 0.0).to_f,
        "message" => meta["message"] || "",
        "playerCount" => meta.fetch("playerCount", pool_count).to_i
      }
      result["message"] = meta["message"] || meta["error"] || "Build failed" if status == "failed"
      result
    end

    # Enqueue cache warm-up for the popular leagues.
    def warmup
      return [] unless TaskQueue.redis_available?

      selections = Config::POPULAR_LEAGUES
      job_id = TaskQueue.enqueue("warm_competitions", [selections])
      [{ "jobId" => job_id, "selections" => selections }]
    end

    # MARK: - Helpers

    def team_id(team_ref)
      team_ref.split("-", 2)[1].to_i
    end

    def find_team(fixtures, team_id)
      target = "sb-#{team_id}"
      fixtures.each do |f|
        return f["home"] if f["home"]["id"] == target
        return f["away"] if f["away"]["id"] == target
      end
      team(team_id, "Team #{team_id}")
    end

    def competition(competition_id, season_id, name)
      {
        "competitionID" => competition_id,
        "seasonID" => season_id,
        "name" => name,
        "country" => "",
        "gender" => "",
        "seasonName" => ""
      }
    end

    private

    def short_name(name)
      letters = name.to_s.upcase.chars.select { |c| c.match?(/[[:alnum:]]/) }
      letters.first(3).join
    end

    def team(tid, name)
      { "id" => "sb-#{tid}", "name" => name, "shortName" => short_name(name), "crestSymbol" => "shield.fill" }
    end
  end
end
