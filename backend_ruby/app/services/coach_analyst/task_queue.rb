require "redis"
require "securerandom"
require "json"

module CoachAnalyst
  # Redis-backed durable job queue, mirroring the RQ/Redis wiring of
  # backend/app/taskqueue.py. Job metadata (status/progress/message) lives in a
  # Redis hash per job so the API can report progress from another process.
  module TaskQueue
    module_function

    def redis_client
      @redis_client ||= Redis.new(url: Config.redis_url)
    end

    def redis_available?
      redis_client.ping
      true
    rescue StandardError
      false
    end

    def job_key(id)
      "#{Config.queue_name}:job:#{id}"
    end

    def enqueue(function_name, args, ttl: 3600)
      id = SecureRandom.hex(12)
      redis_client.multi do |tx|
        tx.hset(
          job_key(id),
          "status", "queued", "progress", "0.0", "message", "Queued…", "playerCount", "0",
          "function", function_name, "args", JSON.generate(args)
        )
        tx.expire(job_key(id), ttl)
        tx.rpush(Config.queue_name, id)
      end
      id
    end

    def update_meta(id, fields = {})
      return if fields.empty?

      redis_client.hset(job_key(id), fields.transform_keys(&:to_s).transform_values(&:to_s))
    rescue StandardError
      nil
    end

    def fetch(id)
      data = redis_client.hgetall(job_key(id))
      data.empty? ? nil : data
    rescue StandardError
      nil
    end

    def reserve(timeout = 5)
      _key, id = redis_client.blpop(Config.queue_name, timeout: timeout)
      id
    end

    def process(id)
      data = redis_client.hgetall(job_key(id))
      function_name = data["function"]
      args = JSON.parse(data["args"] || "[]")
      update_meta(id, "status" => "running", "message" => "Running…")
      Jobs.dispatch(function_name, args, id)
      update_meta(id, "status" => "ready")
    rescue StandardError => e
      update_meta(id, "status" => "failed", "message" => e.message, "error" => e.message)
    end

    def run_worker
      loop do
        id = reserve
        process(id) if id
      end
    end
  end
end
