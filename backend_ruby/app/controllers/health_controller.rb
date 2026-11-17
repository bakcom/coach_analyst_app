class HealthController < ApplicationController
  def show
    render json: {
      "status" => "ok",
      "queue" => CoachAnalyst::TaskQueue.redis_available? ? "redis" : "inline"
    }
  end
end
