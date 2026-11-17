# Coach Analyst BFF domain code, ported 1:1 from the FastAPI backend in
# `backend/`. The Ruby port is maintained for testing and cross-checking the
# Python implementation; it is not intended to run in production.
module CoachAnalyst
  @service_mutex = Mutex.new

  class << self
    # Process-wide ScoutingService with a shared StatsBomb client, mirroring the
    # FastAPI lifespan singleton stored on `app.state.service`.
    def service
      return @service if @service

      @service_mutex.synchronize do
        @service ||= Service.new(StatsBombClient.new)
      end
    end
  end
end
