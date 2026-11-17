class PoolController < ApplicationController
  # GET /pool
  def show
    render json: coach_service.current_pool
  end

  # GET /pool/status
  def status
    render json: coach_service.job_status(params[:jobId].presence)
  end

  # POST /pool/build
  def build
    selections = Array(json_body["selections"])
    if selections.empty?
      return render json: { "detail" => "No competitions selected." }, status: :bad_request
    end

    render json: coach_service.start_build(selections, force: boolean_param(params[:force]))
  end

  # POST /pool/warmup
  def warmup
    render json: coach_service.warmup
  end
end
