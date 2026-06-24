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

  ### Throttle signup POSTs to 5/minute per IP ###
  # Cheap defense-in-depth in front of both the web operator signup form
  # (POST /onboarding/create_user — the GET /signup page just renders it) and
  # the mobile/API member signup (POST /api/v1/auth/signup), independent of
  # Turnstile. A human signs up once; 5/min per IP leaves ample room for
  # typo-retries while capping a credential-stuffing or account-spam loop.
  # Matches the /embed/* limit above.
  SIGNUP_POST_PATHS = ["/onboarding/create_user", "/api/v1/auth/signup"].freeze
  throttle("signup/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.post? && SIGNUP_POST_PATHS.include?(req.path)
  end

  ### Throttle passwordless Login Code requests (ADR 0016) ###
  # Issuing a code emails the user, so cap it two ways: per IP (mirrors the
  # signup limit) and per email address, so an attacker can't defeat the
  # per-code 5-attempt cap by rapidly re-requesting fresh codes, and a victim
  # whose address someone is poking can't be email-bombed. 3 codes / 15 min is
  # ample for a real person mistyping or not seeing the first email.
  # Both the API (mobile) and the web form route through these throttles.
  REQUEST_LOGIN_CODE_PATHS = ["/api/v1/auth/request_login_code", "/login/code"].freeze
  VERIFY_LOGIN_CODE_PATHS = ["/api/v1/auth/verify_login_code", "/login/code/verify"].freeze
  throttle("login_code_request/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.post? && REQUEST_LOGIN_CODE_PATHS.include?(req.path)
  end
  throttle("login_code_request/email", limit: 3, period: 15.minutes) do |req|
    if req.post? && REQUEST_LOGIN_CODE_PATHS.include?(req.path)
      email = req.params["email"].to_s.downcase.strip
      email.presence
    end
  end

  ### Throttle Login Code verification to 10/minute per IP ###
  # Defense-in-depth behind the per-code 5-attempt cap — bounds raw guessing
  # velocity against the 6-digit space.
  throttle("login_code_verify/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.post? && VERIFY_LOGIN_CODE_PATHS.include?(req.path)
  end

  ### Throttle BLE auto-unlock POSTs to 30/minute per Bearer token ###
  # Members walk by repeatedly; 30/min comfortably covers normal traffic
  # while capping a hostile loop. Bearer token includes the user id so this
  # is per-user even before JWT decode.
  throttle("api/v1/auto_unlock/token", limit: 30, period: 1.minute) do |req|
    if req.post? && req.path == "/api/v1/door/auto_unlock"
      req.get_header("HTTP_AUTHORIZATION").to_s.split(" ").last.presence || req.ip
    end
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
