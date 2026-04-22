# Staging-only time travel. Set SIMULATED_TIME (e.g.
# "2026-04-22T06:00:00-07:00") to freeze staging's clock to that
# moment and have it drift forward in real time from there. Backed by
# Timecop so we don't accidentally stack-overflow hand-rolled
# overrides of Time.now.

Rails.application.config.after_initialize do
  if ENV["SIMULATED_TIME"].present?
    begin
      require "timecop"
      origin = Time.zone.parse(ENV["SIMULATED_TIME"])
      raise "could not parse SIMULATED_TIME" unless origin
      Timecop.travel(origin)
      Rails.logger.info("[SimulatedTime] Timecop.travel(#{origin.iso8601}) — drifts from real time")
    rescue => e
      Rails.logger.error("[SimulatedTime] init failed: #{e.class}: #{e.message}")
    end
  end
end
