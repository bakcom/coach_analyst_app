module CoachAnalyst
  # Job functions executed by the queue worker, mirroring backend/app/jobs.py.
  module Jobs
    module_function

    def pool_file
      Config.cache_dir.join("pool.json")
    end

    # Builds the pooled player list and writes it to disk.
    def build_pool_job(selections, force, job_id)
      client = StatsBombClient.new
      profiles =
        begin
          Builder.build_pool_profiles(
            client, selections, force: force,
            progress: ->(fraction, message) { TaskQueue.update_meta(job_id, "progress" => fraction, "message" => message) }
          )
        ensure
          client.aclose
        end
      Storage.write_json_atomic(pool_file, profiles)
      TaskQueue.update_meta(
        job_id,
        "playerCount" => profiles.length, "progress" => 1.0,
        "message" => "Pool ready · #{profiles.length} players"
      )
      profiles.length
    end

    # Precomputes per-competition caches without touching the pool.
    def warm_competitions_job(selections, job_id)
      client = StatsBombClient.new
      count = [selections.length, 1].max
      begin
        selections.each_with_index do |selection, index|
          report = lambda do |fraction|
            TaskQueue.update_meta(job_id, "progress" => (index + fraction) / count, "message" => "Warming #{selection['name']}")
          end
          Builder.ensure_competition_profiles(
            client, selection["competitionID"], selection["seasonID"],
            selection["name"] || "", force: false, progress: report
          )
        end
      ensure
        client.aclose
      end
      selections.length
    end

    def dispatch(name, args, job_id)
      case name
      when "build_pool"
        build_pool_job(args[0], args[1], job_id)
      when "warm_competitions"
        warm_competitions_job(args[0], job_id)
      else
        raise ArgumentError, "Unknown job #{name.inspect}"
      end
    end
  end
end
