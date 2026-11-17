class PlayersController < ApplicationController
  # POST /players/similar
  def similar
    body = json_body
    render json: CoachAnalyst::Metrics.similar(
      normalize_profile(body["profile"]),
      coach_service.current_pool,
      other_competitions_only: body.fetch("otherCompetitionsOnly", true),
      limit: body.fetch("limit", 10)
    )
  end
end
