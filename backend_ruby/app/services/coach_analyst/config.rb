module CoachAnalyst
  # Central configuration read from the environment with sensible defaults.
  # Mirrors `backend/app/config.py`.
  module Config
    module_function

    def flag(name)
      %w[1 true yes on].include?(ENV.fetch(name, "0").downcase)
    end

    # Where StatsBomb JSON and aggregated caches are stored.
    def cache_dir
      @cache_dir ||= begin
        value = ENV["COACH_CACHE_DIR"] || ENV["SB_CACHE_DIR"]
        value ? Pathname.new(value).expand_path : Pathname.new(Dir.home).join(".cache", "coachanalyst-statsbomb")
      end
    end

    def redis_url
      ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0")
    end

    def queue_name
      ENV.fetch("QUEUE_NAME", "coachanalyst")
    end

    def max_matches_per_competition
      Integer(ENV.fetch("MAX_MATCHES_PER_COMPETITION", "24"))
    end

    def auto_warmup
      flag("AUTO_WARMUP")
    end

    # Widely-followed open-data competition seasons used for warm-up.
    POPULAR_LEAGUES = [
      { "competitionID" => 11, "seasonID" => 90, "name" => "La Liga · 2020/2021" },
      { "competitionID" => 2,  "seasonID" => 27, "name" => "Premier League · 2015/2016" },
      { "competitionID" => 9,  "seasonID" => 281, "name" => "1. Bundesliga · 2023/2024" },
      { "competitionID" => 44, "seasonID" => 107, "name" => "Major League Soccer · 2023" },
      { "competitionID" => 72, "seasonID" => 30, "name" => "FIFA Women's World Cup · 2019" }
    ].freeze
  end
end
