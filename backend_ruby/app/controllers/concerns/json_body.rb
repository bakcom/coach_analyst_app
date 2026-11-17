# Shared controller helpers for the Coach Analyst BFF.
module JsonBody
  extend ActiveSupport::Concern

  private

  # The raw JSON body as a plain string-keyed Hash, so the camelCase keys the
  # Swift client sends reach the domain code untouched (matching FastAPI).
  def json_body
    @json_body ||= begin
      raw = request.raw_post
      raw.nil? || raw.empty? ? {} : JSON.parse(raw)
    end
  end

  def coach_service
    CoachAnalyst.service
  end

  # Coerce a StatsBomb/FastAPI-style boolean query param ("1", "true", "on", …).
  def boolean_param(value)
    %w[1 true yes on].include?(value.to_s.downcase)
  end

  # Fill a profile's totals with the full metric key set (defaulting missing
  # keys to 0.0), matching Pydantic's TotalsModel defaults.
  def normalize_profile(profile)
    profile = (profile || {}).dup
    provided = profile["totals"] || {}
    totals = CoachAnalyst::Aggregate.empty_totals(provided.fetch("minutes", 0.0).to_f)
    provided.each do |key, value|
      totals[key] = value.to_f if CoachAnalyst::Aggregate::TOTAL_KEYS.include?(key)
    end
    profile["totals"] = totals
    profile
  end
end
