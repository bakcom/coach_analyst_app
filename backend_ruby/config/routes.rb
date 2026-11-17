Rails.application.routes.draw do
  # Health / liveness
  get "/health", to: "health#show"

  # Catalog
  get "/competitions", to: "competitions#index"
  get "/competitions/:competition_id/:season_id/teams", to: "competitions#teams"
  get "/competitions/:competition_id/:season_id/teams/:team_id/dataset", to: "competitions#dataset"

  # Analytics
  get "/competitions/:competition_id/:season_id/matches/:match_id/analysis", to: "competitions#match_analysis"
  get "/competitions/:competition_id/:season_id/teams/:team_id/analysis", to: "competitions#team_analysis"

  # Pool
  get "/pool", to: "pool#show"
  get "/pool/status", to: "pool#status"
  post "/pool/build", to: "pool#build"
  post "/pool/warmup", to: "pool#warmup"

  # Similarity / comparison
  post "/players/similar", to: "players#similar"
  post "/comparison", to: "comparison#create"

  # Rails' default health check (kept so `rails` tooling still works)
  get "up" => "rails/health#show", as: :rails_health_check
end
