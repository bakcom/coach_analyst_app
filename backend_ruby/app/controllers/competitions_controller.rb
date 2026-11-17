class CompetitionsController < ApplicationController
  # GET /competitions
  def index
    render json: coach_service.competitions
  end

  # GET /competitions/:competition_id/:season_id/teams
  def teams
    render json: coach_service.teams(competition_id, season_id)
  end

  # GET /competitions/:competition_id/:season_id/teams/:team_id/dataset
  def dataset
    render json: coach_service.dataset(competition_id, season_id, competition_name, team_id)
  end

  # GET /competitions/:competition_id/:season_id/matches/:match_id/analysis
  def match_analysis
    render json: coach_service.match_analysis(competition_id, season_id, match_id)
  rescue LookupError => e
    render json: { "detail" => e.message }, status: :not_found
  end

  # GET /competitions/:competition_id/:season_id/teams/:team_id/analysis
  def team_analysis
    render json: coach_service.team_analysis(competition_id, season_id, competition_name, team_id)
  end

  private

  def competition_id = params[:competition_id].to_i
  def season_id = params[:season_id].to_i
  def match_id = params[:match_id].to_i
  def team_id = params[:team_id].to_i

  def competition_name
    params[:name].presence || "#{competition_id}/#{season_id}"
  end
end
