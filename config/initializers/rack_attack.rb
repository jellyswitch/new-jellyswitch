module RackAttackConfig
  # Rack::Attack's default store is Rails.cache, which on Heroku is FileStore
  # (per-dyno). With multiple dynos, throttle counters never sum across them
  # and the rate limit silently no-ops. Use Redis when REDIS_URL is present
  # so all dynos share one set of counters.
  def self.configure_cache_store!
    return if ENV["REDIS_URL"].blank?

    Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
      url: ENV["REDIS_URL"],
      ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE },
    )
  end
end

class Rack::Attack
  ### Throttle /embed/* POSTs to 5/minute per IP ###
  throttle("embed/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.post? && req.path.start_with?("/embed/")
  end

  ### Custom response for throttled requests ###
  self.throttled_responder = lambda do |env|
    [429, { "Content-Type" => "text/plain" }, ["Too many requests. Please wait a minute and try again."]]
  end
end

RackAttackConfig.configure_cache_store!

# Enable in production + test (so we can write a test for it).
# In dev, leave off — local testing of the form shouldn't trigger it.
Rails.application.config.middleware.use Rack::Attack unless Rails.env.development?
