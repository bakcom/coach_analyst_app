require "net/http"
require "json"
require "uri"

module CoachAnalyst
  # Client for the StatsBomb open-data repository (mirrors statsbomb.py).
  #
  # No API key is required. Swapping to the authenticated StatsBomb API is a
  # matter of changing BASE and adding an auth header.
  class StatsBombClient
    BASE = "https://raw.githubusercontent.com/statsbomb/open-data/master/data/"

    def initialize(concurrency: 8, cache: true)
      @concurrency = concurrency
      @cache = cache
      @semaphore = Semaphore.new(concurrency)
      @cache_dir = Config.cache_dir
      @cache_dir.mkpath if cache
    end

    def competitions
      get("competitions.json")
    end

    def matches(competition_id, season_id)
      get("matches/#{competition_id}/#{season_id}.json")
    end

    def lineups(match_id)
      get("lineups/#{match_id}.json")
    end

    def events(match_id)
      get("events/#{match_id}.json")
    end

    # No-op kept for symmetry with the Python `aclose()`; Net::HTTP opens a
    # fresh connection per request.
    def aclose; end

    private

    def cached_path(path)
      @cache_dir.join(path.tr("/", "__"))
    end

    def get(path)
      cached = cached_path(path)
      return JSON.parse(cached.read) if @cache && cached.exist?

      @semaphore.synchronize do
        data = fetch(path)
        cached.write(JSON.generate(data)) if @cache
        data
      end
    end

    def fetch(path)
      uri = URI.parse(BASE + path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 60
      http.read_timeout = 60
      response = http.get(uri.request_uri)
      response.value
      JSON.parse(response.body)
    end
  end

  # Counting semaphore so concurrent fetches never exceed the configured limit.
  class Semaphore
    def initialize(limit)
      @limit = limit
      @count = 0
      @mutex = Mutex.new
      @condition = ConditionVariable.new
    end

    def synchronize
      @mutex.synchronize do
        @condition.wait(@mutex) while @count >= @limit
        @count += 1
      end
      begin
        yield
      ensure
        @mutex.synchronize do
          @count -= 1
          @condition.signal
        end
      end
    end
  end
end
