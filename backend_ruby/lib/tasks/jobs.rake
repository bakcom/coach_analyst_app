namespace :jobs do
  desc "Run the durable Redis job worker (pool builds / cache warm-up)"
  task work: :environment do
    CoachAnalyst::TaskQueue.run_worker
  end
end
