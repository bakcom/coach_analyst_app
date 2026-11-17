class ComparisonController < ApplicationController
  # POST /comparison
  def create
    body = json_body
    render json: CoachAnalyst::Metrics.comparison(
      normalize_profile(body["target"]),
      normalize_profile(body["candidate"]),
      coach_service.current_pool
    )
  end
end
